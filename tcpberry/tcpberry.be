#-
© Panagiotis Karagiannis MIT Licence
Upload berry code to tasmota using a TCP socket
https://github.com/pkarsy/tcpberry
-#

# We encapsulate all functionality inside a function. This way we pollut
# the global namespace as little as possible
def tcpberry_func()
  import strict
  import string
  import crc
  var brmsg = 'TCPB : '
  #
  # This is useful when developing tcpberry itself
  # we stop the old instance before we create the new one
  # allowing the garbage collector to work
  if global.tcpberry!=nil
      global.tcpberry.deinit()
  end
  # a singleton only one instance is active at any time
  class TCPBERRY
    # Contains the listening(server) socket, or nil if the server is disabled
    var server
    # If a client is connected contains the TCP socket, otherwise is nil
    var conn
    # We use a variable to store the closure, this way we can cancel it anytime
    var fast_loop_closure
    # finite state machine. The machinery is in fast_loop() member function
    var state
    # holds the expected file size from STATE-1
    var bufsize
    # Contains the remotely uploaded file as a string (STATE-2)
    var buf
    # The CRC we get from berryuploader
    var remote_crc
    # We use it to detect timeout (2000ms at the moment)
    var millis
    # Contains the filename (SAVE command)
    var filename

    def init()
      self.fast_loop_closure = def () self.fast_loop() end # see comment on declaration
      # 
      tasmota.add_rule('Wifi#Disconnected', /->self.stop(), self)
      # If we try to create a server socket when wifi is not connected
      # The whole berry engine goes down (observed with Tasmota 14.1)
      # This is probably normal, and there is no reason to start the
      # server without actually having a wifi connection
      if tasmota.wifi('up')
        # If the wifi is connected, we start the server immediatelly
        self.start_server()
      else
        # We will create the server when wifi is up
        tasmota.add_rule('Wifi#Connected', /->self.start_server(), self)
        return
      end
    end
    #
    def start_server()
      self.state = 1
      self.buf=''
      self.filename = nil
      self.millis = 0
      var port = 1001
      self.server = tcpserver(port)
      # We need add_driver() to use the every_50ms() method
      tasmota.add_driver(self)
      log('' .. brmsg .. 'Listening on ' .. tasmota.wifi('ip') .. ':' .. port)
    end
    #
    # normally it is not used, only when developing TCPBERRY itself
    # and reloading the server again and again
    def deinit()
      log(brmsg + 'deinit()')
      self.stop()
      # allowing the BerryVM to free the resources
      tasmota.remove_rule('Wifi#Connected', self)
      tasmota.remove_rule('Wifi#Disconnected', self)
    end
    # like deinit(), this is used when developing TCPBERRY
    def stop()
      if self.server != nil
        log(brmsg + 'Server stopped')
        self.server.close()
        self.server = nil
      end
      self.close_client_conn()
      tasmota.remove_driver(self)
      tasmota.remove_fast_loop(self.fast_loop_closure)
    end
    #
    # The function is running as long as the tcpberry.be is loaded.
    # There is no measurable hit on the system responsivness when it is running
    def every_50ms()
      if self.millis>0 && tasmota.millis()-self.millis>2000
        self.end_upload('Timeout')
      end
      ## TODO timeout here
      if self.server.hasclient() # No callback in server socket, so we have to check it periodically
        var conn = self.server.accept()
        if self.conn!=nil
          conn.close()
          log(brmsg + 'Second client is dropped')
          return
        end
        self.conn = conn
        log(brmsg + 'Connection accepted')
        tasmota.add_fast_loop(self.fast_loop_closure)
      end
    end
    #
    # This function is running as fast as possible but only when there is a client uploading code
    # Even then there isnt any noticeable performance loss. Normally a callback is doind the job of handling
    # incoming data but I thing tasmota berry at the moment (6/24) does not have this for sockets.
    # Note that even this way it is working perfectly, so no rush to "inprove" this code
    def fast_loop()
      var s = self.conn.read(2048)
      if !s
        if !self.conn.connected()
          # With LAN connections is very rare to see this
          self.end_upload('Connection was closed unexpectedly')
        end
        return # There are no new data, so no need to continue
      end
      #
      self.buf += s # The new socket data are appended to the buffer
      self.millis = tasmota.millis()
      if self.state == 1 # Waiting for the header
        if size(self.buf)<16 return end # We need at least the header
        var cmd = self.buf[0..1]
        self.bufsize = int('0x' + self.buf[2..7])
        self.remote_crc = int('0x' + self.buf[8..15])
        self.buf = self.buf[16..]
        if cmd == 'CR'
          self.state = 3
          self.conn.write('HEADER OK')
          return
        elif cmd == 'CS'
          self.state = 2
        else
          return self.end_upload('Unrecognized command')
        end
        #self.conn.write('' .. brmsg .. 'goclient CRC = ' .. self.remote_crc .. '\n')
      end
      #
      if self.state == 2 # filename
        if size(self.buf)<4 return end
        if self.buf[-3..-1] != '.be' return end
        self.filename = self.buf
        self.conn.write('HEADER OK')
        self.buf = ''
        self.state = 3
        return
      end
      if self.state == 3 # Waiting for the berry scode
          var sz = size(self.buf)
          if sz==self.bufsize
            self.conn.write('' .. brmsg .. 'Transfered ' .. self.bufsize .. ' bytes\n')
            if self.remote_crc != self.calc_crc()
              return self.end_upload('CRC is incorrect')
            end
            var fun
            try
              fun = compile(self.buf) # we may have errors here
              self.conn.write(brmsg + 'No compile errors\n')
            except .. as err, msg
              return self.end_upload(brmsg + 'Compile error, ' + err + '\n' + msg + '\n')
            end
            if fun == nil
              return self.end_upload('Error, compile returned nil')
            end
            try
              fun() # we may we have runtime errors here
              self.conn.write(brmsg + 'No runtime errors\n')
              self.conn.write('' .. brmsg .. 'MEMUSED=' .. tasmota.gc() .. ', MEMFREE=' .. tasmota.get_free_heap()
              .. '\n')
              if !self.filename
                return self.end_upload(nil,"SUCCESS")
              end
              #return self.end_upload('' .. brmsg .. 'No runtime errors\n' .. brmsg ..
              #'MEMUSED=' .. tasmota.gc() .. ', MEMFREE=' .. tasmota.get_free_heap() ,"SUCCESS") 
            except .. as err, msg
              #self.conn.write(brmsg + 'Runtime error : ' + err + '\n')
              #self.conn.write('' + msg + '\n')
              return self.end_upload('' .. brmsg .. 'Runtime error : ' .. err .. '\n' .. msg .. '\n')
            end
            try
              var f = open(self.filename, 'w')
              f.write(self.buf)
              f.close()
              return self.end_upload('The file "' .. self.filename .. '" is stored', 'SUCCESS')
            except .. as err, msg
              return self.end_upload('Error = ' .. err .. ' msg = ' .. msg)
            end
          elif sz>self.bufsize
              var msg = brmsg + 'Got more data than the file size'
              return self.end_upload(msg)
          else
            # sz < self.bufsize witch means wait for more data
          end
      end
      # if no one of the previous conditions occured
      # The fast_loop will still be active and will be called after about 5ms
    end
    #
    def close_client_conn(msg, endmsg)
      if self.conn == nil
        log(brmsg + 'socket is already closed')
        return
      end
      log(brmsg + 'Closing client connection')
      if msg != nil
        log(brmsg + msg)
        self.conn.write(brmsg+msg+'\n')
      end
      if endmsg == nil
        endmsg = 'ERROR'
      end
      self.conn.write(endmsg)
      self.conn.close()
      self.conn = nil # This way we know when the socket is closed
    end
    #
    def end_upload(msg,endmsg)
      self.close_client_conn(msg,endmsg)
      tasmota.remove_fast_loop(self.fast_loop_closure)
      self.state = 1
      self.buf = ''
      self.filename = nil
      self.millis = 0
    end
    #
    # We use the crc to check that the incoming file is not corrupted.
    def calc_crc()
      var step = 1000
      var c = 0
      var left = 0
      while left < self.bufsize
        var right = left + step - 1
        if right >= self.bufsize
          right = self.bufsize - 1
        end
        var dat = bytes(step) .. self.buf[left .. right]
        c = crc.crc32(c, dat)
        left += step
      end
      return c
    end
    #
  end
  #
  global.tcpberry = TCPBERRY()
  #
end

# Creates a TCPBERRY instance called tcpberry (global var)
tcpberry_func()
# We prevent the creation of other instances
tcpberry_func = nil
