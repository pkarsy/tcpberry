#-
The module implements a blinking LED
It is somewhat overengineered and I am sure there are other/better methods
to blink a LED
but the main purpose is to show how to develop a driver/module using tcpberry for uploads
The BLINK object allocates a timer to signal the ON->OFF or OFF->ON process
If we replace the BLINK class without stoping the timers the old object remains active
and many instances compete for the same PIN. Also the BerryVM uses more memory on evey upload
end enetually is crashing.
The idea is to free the BerryVM resources (timers triggers cronjobs) before redeclaring
the BLINK class. The Berry garbage collector can then do its job, and we can have as many live updates
as we like.
For actual usage :
Upload blink.be with tcp/mqttberry (upload-blink -s) or use the web file manager
in autoexec.be we add :
load('blink')
var led=BLINK(2).start(100,200) # For a led in pin 2 100ms ON - 200ms OFF
-#

################### CLEAN OLD INSTANCE ON LIVE UPDATES ##################
# We basically remove all timers from tasmota._timers
# The first time we upload the code, there is nothing to remove
# but subsequent live updates will remove all previous instances
# The stop_all static method facilitates this
if global.BLINK != nil
    global.BLINK.stop_all()
end
#########################################################################

# The BLINK class. 
class BLINK

  var pin # The ESP32 pin the LED is connected
  var state # the current state of the LED.
  var timer_closure # we save it to a var to be able to cancel
  var t1, t2 # ON,OFF time
  var ON, OFF # = gpio.HIGH/LOW. If led is inverted LOW/HIGH

  def init(pin, inverted) # pass inverted = true for active low LEDs
    self.pin = pin
    if inverted
        self.ON = gpio.LOW
        self.OFF = gpio.HIGH
    else
        self.ON = gpio.HIGH
        self.OFF = gpio.LOW
    end
    self.timer_closure = def () self._run() end # we save the closure so we can cancel the timer if we want
    self.state = self.OFF
    gpio.pin_mode(self.pin, gpio.OUTPUT)
    gpio.digital_write(self.pin, self.state) # We start with the LED -> OFF
  end
  
  def start(t1, t2)
    if t1==nil || int(t1)<=0 print('blink time is missing/incorrect') return end
    t1=int(t1)
    if t2==nil
        t2=t1
    else
        t2=int(t2)
    end
    if t2==0 print('time t2 cannot be 0') return end
    tasmota.remove_timer(self)
    self.t1=t1
    self.t2=t2
    self.state=self.OFF
    self._run()
    return self
  end
  
  def blink(t1,t2)
    return self.start(t1,t2)
  end
  
  def on()
    tasmota.remove_timer(self)
    self.state = self.ON
    gpio.digital_write(self.pin, self.state)
    return self
  end
  
  def off()
    tasmota.remove_timer(self)
    self.state = self.OFF
    gpio.digital_write(self.pin, self.state)
    return self
  end

  # Not to be called by the user
  def _run()
    if self.state==self.ON
      self.state=self.OFF
      tasmota.set_timer(self.t2, self.timer_closure, self)
    else
      self.state=self.ON
      tasmota.set_timer(self.t1, self.timer_closure, self)
    end
    gpio.digital_write(self.pin, self.state)
  end

  # To be able to see the garbage collector in action
  # Not useful for actual use but very useful on live updates
  def deinit()
    print('BLINK(' .. self.pin .. ') deinit')
    # we do not put stop() here as the pin is shared and it will interfere with the new module
  end
  # LIVE UPDATES HELPER
  # 
  static def stop_all()
    if tasmota._timers
      var timers = tasmota._timers[0..] # copy
      for i:timers
        if type(i.id)=='instance' && classname(i.id)=='BLINK'
          print('Turn OFF BLINK(' .. i.id.pin .. ')')
          i.id.off()
        end
      end
    end
  end
end

# esp32 lolin lipo buildin active low LED on PIN 22 
# led = BLINK(22, true) # The true means OUTPUT_LOW -> LED_ON
# led.blink(100,1000) # 100ms ON and 1000ms OFF

# esp32c3 core luatos buldin leds on pins 12 and 13
led1 = BLINK(12).blink(500,1000)
led2 = BLINK(13).blink(500,1010)

# esp32-s2 wemos buldin led
# BLINK(15).blink(500,1000)
