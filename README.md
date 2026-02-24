# Live over the air (OTA) updates for Tasmota Berry code

## Why tcpberry?

Tasmota's Berry scripting offers an accessible way to automate tasks that don't need millisecond precision. The Tasmota system handles all the boring infrastructure - WiFi, MQTT, GPIO, sensors - allowing you to focus your Berry code purely on your application's logic.

However, the standard development workflow is slow: edit, save to flash, reboot, check. This tool aims for **productivity** by enabling a fast **edit → run → feedback** loop. Code uploads in seconds and executes immediately in RAM - no flash wear, no reboots.

The TCP version gives you almost instant uploads when working on your local network. The MQTT version goes further, allowing remote upgrades from anywhere - even across different networks. If the code misbehaves, you can fix and redeploy without physical access to the device.

This way you can edit Tasmota/Berry code with the convenience of VSCode (or similar) and upload and see the results immediately.

Do not confuse this with Tasmota OTA updates, which update the tasmota system itself (including the berry interpreter).

The repository contains 2 Berry modules that can be installed on a Tasmota ESP32x system

## tcpberry (ESP32x daemon written in Berry)

Opens a TCP 1001 port on the ESP32(-C3, S2, S3) and waits for code from the PC. It is very fast, almost instant, and is probably the most convenient solution when developing.

The developer must be at the same LAN, and there is no authentication or encryption, so probably can only be used in a LAN (probably home) controlled by the developer.

For other networks, using your mobile phone as an access point is usually the simplest solution.

However for remote uploads the most powerful solution is mqttberry.

## mqttberry (ESP32x daemon)

Does the same job as tcpberry, but uses 2 MQTT topics

```sh
mqttberry/MyTasmotaTopic/upload
mqttberry/MyTasmotaTopic/report
```

The first is for code uploads, and the second for answers.

It is slower than tcpberry (but still perfectly OK) and needs 2-3 seconds for a 5-10K script when using an external MQTT server like Flespi or HiveMQ. It is way faster using a LAN MQTT broker (but in that case use tcpberry). There are some advantages using this option:

- The developer and the ESP32 can be in different networks (home-work, for example, or home-mobile). No need for port forwarding, etc.
- The communication is encrypted (if using MQTT-TLS) and authenticated.
- No open ports on ESP32, allowing mqttberry to run even in production environments, but you need to be careful not to break the functionality with buggy code.

## berryuploader

This is the PC-side program that performs the upload.

It is not designed to run directly; it does not accept command-line arguments, only environment variables. You need to have a shell script in a project directory and the script sets the environment and calls the berryuploader. Each example contains such a shell script. You can modify and use it for your projects.

The uploader can work with a TCP socket (tcpberry must be running on the ESP) or MQTT messages (mqttberry must be running). Probably you want to have both servers in parallel.

The repository contains the berryuploader executable precompiled for Linux and Windows. You can compile it yourself but you need Go installed. WARNING: Windows scripts are not included. If you can create them, send me a note.

## Installation

### Developer machine side

#### PC: (Instructions for linux)

```sh
cd ~/Programming # Use any dir you prefer
git clone https://github.com/pkarsy/tcpberry
# Now will put berryuploader to the PATH
cd ~/bin # Or anywhere you prefer in PATH
ln -s ~/Programming/tcpberry/berryupload/berryupload .
```

#### Mac OS (Apple Silicon)

It assumes you have already installed brew and berry interpreter.

```sh
cd ~/Documents/Berry\ Tasmota/ # Use any dir you prefer
git clone https://github.com/pkarsy/tcpberry
# Now we will recompile berryuploader for Apple Silicon Mac. It assumes you have Go installed. If not, run `brew install golang`.
cd tcpberry/berryupload
go build
ls -al # Make sure new date and time is next to berryupload file. It means the file was successfully rebuilt. You can also try to run it ./berryupload - it should return an error about missing UPLOAD_MODE env var.
cd ../example-trivial
vi upload-trivial  
```

Go to the last line and replace `berryupload` with `~/Documents/Berry\\ Tasmota/tcpberry/berryupload/berryupload`.

### ESP32x side:

Upload "tcpberry.be" and "mqttberry.be" to the filesystem. In "autoexec.be" add the lines

```sh
load('tcpberry')
load('mqttberry')
```

Each load starts the corresponding daemon.
You can have both of them or only one. Reset the module.

Now let's run the first example

```sh
cd ~/Programming/tcpberry/example-trivial
edit the "upload-trivial" shell script and set the parameters
./upload-trivial
```

## Important Code Guidelines

Uploading code with tcp/mqttberry is like copying and pasting in the Berry Scripting Console.

**You cannot upload just any code, and expect live updates to work !**

tcp/mqttberry does not remove old objects and/or Tasmota resources automatically for you. In many cases, this indeed happens by the BerryVM (the garbage collector); see the example-trivial for this.

If the code allocates timers, cronjobs, triggers, network sockets etc, then the code you upload should de-allocate all those resources, before re-declaring the classes or functions. The following berry modules work this way :

- example-blink (LED blink) in this repository, contains comments and code of how you can accomplish this.
- mqttberry itself is written with this logic and can be live updated with tcpberry
- tcpberry can be live updated with mqttberry
- [TasmotaBerryTime](https://github.com/pkarsy/TasmotaBerryTime) Contains two RTC (real time clock) drivers, each one has an upload script using tcp/mqttberry

A good practice is that you do not want to pollute the global namespace with variables, objects, etc. Encapsulate the functionality in a function or class. Even a class with its instances and helper variables and functions can be encapsulated in a function. The above examples do this of course; check them out.

Live updates do not work with code designed to be loaded with import:

```bash
import myModule # Only works once
```

You have to design your code to be loaded with

```bash
load("myModule") # tries to load the code every time
```

## Code save

When we have finished editing the Berry script, we can also save it to the ESP32.

All upload scripts "upload-blink" etc. accept the "-s" option. Look at the upload script itself
to see how the -s option works.

Saving the script does not imply auto-executing the code. You have to edit `autoexec.be` manually.

## TODO. Any help is welcome

- Configure VSCode to upload the code with some keyboard combination. At the moment, type `./upload-xyz`.
- Probably the messages from tcp/mqttberry should have a format understandable by the editor to show the syntax errors directly in the editor.
- Windows and Mac Instructions for Installing/Uploading.
