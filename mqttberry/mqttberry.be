#-
© Panagiotis Karagiannis MIT Licence
Upload berry code to tasmota using a MQTT messages
https://github.com/pkarsy/tcpberry
-#

# We encapsulate all functionality inside a function. This way we pollut
# the global namespace as little as possible
def mqttberry_func()
  #
  import strict
  import string
  import mqtt
  import crc
  #
  var brmsg = 'MQTB : '
  #
  # When developing mqttberry itself, we want live updates so
  # we stop the old instance before we create the new one
  if global.mqttberry != nil
      # Removes MQTT subscriptions, so the module becomes inactive
      # and when we redeclare it, the BerryVM (the garbage collector) can recycle it
      global.mqttberry.stop()
  end
  # a singleton only one instance is active at any time
  class MQTTBERRY
    var state # finite state machine. See process_message()
    var bufsize # holds the remotely given file size
    var buf # Contains the remotely uploaded file as a string
    var topic
    var publish # mqttberry sends messages
    var millis # To detect timeouts
    var remote_crc # CRC32 to confirm the script is correctly transfered.
    var filename
    #
    def init()
      var topic = tasmota.cmd('Topic', true)['Topic']
      self.topic = 'mqttberry/' + topic + '/upload' # TODO devel calculate
      self.publish = 'mqttberry/' + topic + '/report'
      mqtt.subscribe(self.topic, /topic,idx,pkt->self.process_message(pkt) )
      self.state = 1
      self.buf=''
      self.millis = 0
      log(brmsg + 'Waiting for berry code via MQTT ' + self.topic)
    end

    # Used when developing MQTTBERRY, see comment at top
    # it is stopping mqtt.subscribe allowing to remove the module
    # without leaving traces
    def stop()
      self.buf = ''
      self.state = 1
      self.filename = nil
      mqtt.unsubscribe(self.topic)
    end
    #
    # As packets arrive from berryupload this function process them
    def process_message(pkt) #should return true to prevent tasmota from processing the message
      if self.state==2 && tasmota.millis()-self.millis>2000 # TODO -> every 50ms
        self.buf=''
        if self.state==2
          print('Detected stalled upload, rejecting')
          self.state = 1
        end
        self.filename = nil
      end
      if size(pkt)==0
        return self.end_upload('Error empty packets not allowed')
      end
      #
      if self.state == 1
        if size(pkt)<16
          return self.end_upload('Very short packet (less than 16 bytes)')
        end
        var cmd = pkt[0..1]
        self.bufsize = int('0x' + pkt[2..7])
        self.remote_crc = int('0x' + pkt[8..15])
        #print(self.bufsize, self.remote_crc)
        pkt = pkt[16..]
        if cmd == 'CR'
          if size(pkt) != 0
            return self.end_upload('packet size is > 16 bytes')
          end
        elif cmd == 'CS'
          if size(pkt)>3 && pkt[-3..-1]=='.be'
            self.filename = pkt
            # print("Got filename", self.filename)
            # mqtt.publish(self.publish, 'HEADER OK') # This is mandatory for berryupload to continue sending packets
            # self.state = 2 # actual code
            # return
          else
            return self.end_upload('No filename given')
          end
        else
          return self.end_upload('Unrecognized command')
        end
        mqtt.publish(self.publish, 'HEADER OK') # This is mandatory for berryupload to continue sending packets
        self.state = 2 # actual code
        self.millis = tasmota.millis() # To detect timeouts
        return
      end
      #
      self.buf += pkt # Due to restrictions on many mqtt servers, code is coming in multiple parts
      #
      if self.state == 2 # Waiting for the berry script contents
        self.millis = tasmota.millis()
        var sz = size(self.buf)
        #
        if sz < self.bufsize return true end # waiting for more packets
        #
        if sz>self.bufsize # We abort the download of the script
          return self.end_upload('More data than expected ' .. sz .. ' ' .. self.bufsize)
        end
        #
        # We have the script as a whole, with correct size
        #var buf = self.buf # we store it in a var
        #self.buf=''
        mqtt.publish(self.publish, 'Transfered ' .. self.bufsize .. ' bytes')
        if self.remote_crc != self.calc_crc()
          #var msg= brmsg +'CRC is incorrect'
          #log(msg)
          self.end_upload('CRC is incorrect')
          return
        end
        var fun # will hold the compiled code as a function ready to run
        try
          fun = compile(self.buf) # we mey have error here
          mqtt.publish(self.publish, brmsg + 'No compile errors')
        except .. as err, msg
          # mqtt.publish(self.publish, 'err=' .. err .. ' msg=' .. msg)
          return self.end_upload('err=' .. err .. '\nmsg=' .. msg)
        end
        #self.buf = ''
        if fun == nil
          return self.end_upload('compilation returns nil')
        end
        # Now fun != nil
        try
          fun() # we may have runtime errors here
          mqtt.publish(self.publish, brmsg + 'No runtime errors')
          mqtt.publish(self.publish, '' .. brmsg .. 'MEMUSED=' .. tasmota.gc() .. ', MEMFREE=' .. tasmota.get_free_heap())
          # TODO mqtt msg
        except .. as err, msg
          #mqtt.publish(self.publish, 'Runtime error : ' .. err)
          #mqtt.publish(self.publish, '' .. err)
          self.end_upload('Runtime error : ' .. err .. '\n' .. msg)
        end
        if self.filename # Which means we have to save the file
          try
            var f = open(self.filename, 'w')
            f.write(self.buf)
            f.close()
          except .. as err, msg
            return self.end_upload('Error = ' .. err .. ' msg = ' .. msg)
          end
          # 'CS' ends here
          return self.end_upload('The file "' .. self.filename .. '" is stored', 'SUCCESS')
        end
        return self.end_upload(nil, 'SUCCESS')
      end
    end

    def end_upload(msg, endmsg)
      # self.close_client_conn(msg)
      # tasmota.remove_fast_loop(self.fast_loop_closure)
      self.state = 1
      self.buf = ''
      self.filename = nil
      if msg
        log(brmsg + msg)
        mqtt.publish(self.publish, brmsg+msg)
      end
      if endmsg==nil endmsg='ERROR' end
      mqtt.publish(self.publish, endmsg)
      return true # to prevent tasmota from processing the message
    end
    #
    # We need the crc to check that the incoming file is not corrupted when
    # trransfered.
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
  # We need just one instance
  global.mqttberry = MQTTBERRY()
  #
end

# Creates a MQTTBERRY instance called mqttberry (global var)
mqttberry_func()
# We prevent the creation of other instances
mqttberry_func = nil

 #
    # The function is running as long as the driver is loaded.
    # There is no measurable hit on the module responsivness when is running
    # The best solution would be to use a callback in server socket but I think
    # berry does not implement this
    #- def every_50ms()
      if self.server.hasclient() # No callback in server socket, so we have to check it periodically
        var conn = self.server.accept()
        if self.conn!=nil
          conn.close()
          log(brmsg .. '2nd client is dropped')
          return
        end
        self.conn = conn
        log(brmsg .. 'Connection accepted')
        tasmota.add_fast_loop(self.fast_loop_closure)
      end
    end -#
    #
    # This function is running as fast as possible but only when there is a client uploading code
    # Even then there isnt any noticeable performance loss.
    #
    #- def close_client_conn(msg)
      if self.conn != nil
        log(brmsg .. 'Closing client connection') # We can print the remote IP here if we want.
        if msg!=nil
          self.conn.write(msg)
          self.conn.write('\n')
        end
        self.conn.close()
        self.conn = nil
      end
    end -#
    #

          #-if self.server != nil
        log(brmsg .. 'Server stopped')
        self.server.close()
        self.server = nil
      end
      self.close_client_conn()
      tasmota.remove_driver(self)
      tasmota.remove_fast_loop(self.fast_loop_closure) -#
      #tasmota.remove_rule('Wifi#Connected', self)
      #tasmota.remove_rule('Wifi#Disconnected', self)

    #
    #- def create_server()
      self.state = 1
      self.buf=''
      #var port = 1001
      self.server = tcpserver(port)
      # We need add_driver() to use the every_50ms() method
      # tasmota.add_driver(self)
      log(brmsg .. 'Listening on ' .. tasmota.wifi('ip') .. ':' .. port)
    end -#
    #

      #self.fast_loop_closure = def () self.fast_loop() end # see comment on declaration
      # 
      #tasmota.add_rule('Wifi#Disconnected',/->self.stop(), self)
      # If we try to create a server socket when wifi is not connected
      # The whole berry engine goes down (Tasmota 14.1)
      # Indeed, there is no meaning to start the
      # server without actually having a wifi connection
      #if !tasmota.wifi('up')
        # We will create the server when wifi is up
      #  tasmota.add_rule('Wifi#Connected',/->self.create_server(), self)
      #  return
      #end
      # If however the wifi is already up we create the server immediatelly
      #self.create_server()
    # Contains the listening(server) socket, or nil if the server is disabled
    #var server
    # If a client is connected contains the TCP socket, otherwise is nil
    #var conn
    # We use a variable to store the closure, this way we can cancel it anytime
    #var fast_loop_closure

                #self.conn.write(brmsg + 'Compile error : ' + err + '\n')
            #self.conn.write(msg + '\n')
                    #if idx < 0
        #  # no # at end
        #  return true
        #end
        #pkt=pkt[2..]
        #var idx = string.find(pkt, '#')
        #if idx <= 0 || idx > 6
        #    var msg = 'No valid file size given'
        #    log(brmsg .. msg)
        #    return self.end_upload(msg)
        #end
        #self.bufsize = int(pkt[0..idx-1])
        #pkt=pkt[16..]
        #if cmd == 'CR'
        #if pkt != ''
        #  var msg = brmsg + 'Header should be 16 bytes long'
        #  log(msg)
        #  return self.end_upload(msg)
        #end