# Live over the air (OTA) updates for Tasmota Berry code

Develop Berry code on the convenience of VScode(or similar) and upload and run it immediatelly. The code is loaded to ESP32 memory so no flash wear is happening.

Do not confuse this with Tasmota OTA updates which update the tasmota system itself (including the berry interpreter).

The repository contains 2 Berry modules that can be installed on a a tasmota ESP32x system

## tcpberry (a ESP32x Berry Script)

Opens a tcp 1001 port on the ESP32(-c3 s2 s3) and waits for code from the PC. It is very fast almost
instant uploads, and is probably the most convenient solution when developing.

The drawback is of course that the developer has to be at the same LAN, and there is no authentication or encryption, so probably can only be used in a LAN (realistically only home) controlled by the developer.

For other networks the use of tcpberry is a hit or miss process. It is not easy to find the IP of the ESP32 as MDNS is unreliable on a lot of networks. The most reliable way I found is to query the IP using MQTT, for example :

```bash
pub cmnd/tasmotaTopic/webserver
```

Then there is a myriad of network configurations, most Access Points create their own NAT and obviously the laptop and the ESP must be connected to the same AP (Which is not certain if you are on a Work or Public network).

And finally there are Access Points isolating the clients (as a security measure) blocking all direct protocols including tcpberry. Probably the most realistic way of using tcpberry on those cases, is using your mobile phone as Access Point for your PC/Laptop and for ESP32.

However the most simple solution is mqttberry.

## mqttberry (a ESP32x Berry Script)

Does the same job as tcpberry but uses 2 MQTT topics

```sh
mqttberry/MyTasmotaTopic/upload
mqttberry/MyTasmotaTopic/report
```

thr first for code uploads and the second for answers.

It is slower than tcpberry (but still perfectly OK) and needs 2-3 seconds for a 5-10K script when using a external mqtt server like flespi or hivemq. It is way faster using a LAN mqtt broker (but in that case use tcpberry). There are many advantages using this option :

- The developer and the ESP32 can be in different networks (home-work for example or home-mobile), No need for port forwardings etc.
- The communication is encrypted (if using MQTT-TLS) and authenticated.
- No open ports on ESP32 allowing the mqttberry to run even on production environments (But you need to be careful not to brick the module with buggy code).

## berryuploader

This is the PC-side program that performs the upload.

It is not designed to run directly, it does not accept command line arguments, only environment variables. The idea is to have a shell script in a project directory and the script sets the environment and calls the berryuploader. The examples contain such a shell script. You can modify and use it for your projects.

The uploader can work with a TCP socket (tcpberry must be loaded on the ESP) or MQTT messages (mqttberry must be loaded). Probably you want to have both servers running on the ESP32.

The repository contains the berryuploader executable precompiled for linux and windows. You can compile it yourself but you need golang installed.

## Installation

PC side : (Instructions for linux)

```sh
cd ~/Programming # Use any dir you prefer
git clone https://github.com/pkarsy/tcpberry
# Now will put berryuploader to the PATH
cd ~/bin # Or anywher you prefer in  PATH
ln -s ~/Programming/tcpberry/berryupload/berryupload .
```

ESP32x side: Upload "tcpberry.be" and "mqttberry.be" to the filesystem. In "autoexec.be" add the lines

```sh
load('tcpberry')
load('mqttberry')
```

You can have both of them or only one. Reset the module.

Now lets run the first example

```sh
cd ~/Programming/tcpberry/example-trivial
edit the "upload-trivial" shell script and set the parameters
./upload-trivial
```

## Important Code Guidelines

Uploading code with tcp/mqttberry, is like copy-paste in the Berry Scripting Console.

<b>You cannot upload just any code you write and expect live updates to work.</b>

tcp/mqttberry does not remove old objects and/or tasmota resources automatically for you. In many cases this indeed happens by Berry Garbage Collector, see the example-trivial for this.

If the code allocates timers, cronjobs, triggers or network sockets etc, then the code you upload should deallocate all those resources, before redeclare the classes or functions. The following berry modules work this way :

- example-blink (LED blink) contains comments and code of how you can acomplish this.
- ds3231 (TODO Link)
- gnsstime (TODO LINK)
- mqttberry itself is written with this logic and can be live updated with tcpberry
- tcpberry can be live updated with mqttberry

 A good practice is that you do not want to pollute the global namespace with variables objects etc. Encapsulate the functionality in a function or class. Even a class with its instances and helper variables and functions can be encapsulated in a function. The above examples do this of course, check them out.

Live updates do not work with code designed to be loaded with import:

```bash
import myModule # Only works once
```

You have to use

```bash
load("myModule")
```

## Code save

When we have finished editing the berry script, we can also save it to ESP32.

All upload scripts "upload-blink" etc. accept the "-s" option. Look at the upload script itself
to see how the -s option works.

Saving the script does not imply auto-executing the code. You have to edit "autoexec.be" manually.

## TODO. Any help is welcome

- Configure VScode to upload the code with some keyboard combination. At the moment type ./upload-xyz .
- Probably the messages from tcp/mqttberry should have a format understandable by the editor to show the syntax errors directly on the editor.
- Windows and Mac Instructions for Installing/Uploading.
