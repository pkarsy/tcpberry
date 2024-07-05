#-
This should be the first code you upload using tcpberry ot mqttberry

- install tcpberry (PC and ESP32 parts)
- Edit upload-trivial (the shell script)
- Open in the web browser the Berry Scripting Console (To view the messages)
- upload with ./upload-trivial.
- Change the printed messages below and upload again
- If you want to save your code to ESP, type ./upload-trivial -s

This particular code does not allocate anything (timers, crons, sockets)
When we re-upload the code, the garbage collector can freely drop the old objects.
We can see this, when the GC calls deinit()
For a more advanced example see example-blink
-#

class ACLASS

  def init()
    print('ACLASS init() is called (object created)')
  end
  
  def amember()
    print('amember() member function of ACLASS instance called')
  end

  def deinit()
    print('deinit() of ACLASS instance is called (The object is destroyed by GC)')
  end

end

##############

# This function also can easily redeclared without leaving traces
# There is no deinit() here so we dont know when garbage collector works
# but we can check that the used memory does not grow
def afunc()
  print('afunc() called')
end

##############

# We have a demonstartion in Berry Scripting Console
var a = ACLASS()
a.amember()
afunc()

