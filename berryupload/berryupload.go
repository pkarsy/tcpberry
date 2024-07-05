package main

import (
	"bytes"
	"fmt"
	"hash/crc32"
	"io"
	"math/rand"
	"net"
	"os"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
)

var termChan = make(chan struct{})
var contChan = make(chan struct{})

var rcvMessage mqtt.MessageHandler = func(client mqtt.Client, msg mqtt.Message) {
	m := string(msg.Payload())
	if m == "HEADER OK" {
		fmt.Println("Server responded")
		contChan <- struct{}{} // tcp_upload and mqtt_upload wait for this to continue
		return
	}
	if m == "SUCCESS" {
		fmt.Println("Operation completed succesfully")
		termChan <- struct{}{}
		return
	}
	if m == "ERROR" {
		fmt.Println("Operation failed")
		termChan <- struct{}{}
		return
	}
	// All other server responses are printed
	fmt.Println(m)
}

var connectHandler mqtt.OnConnectHandler = func(client mqtt.Client) {
	fmt.Println("Connected to mqtt broker")
}

var connectionLostHandler mqtt.ConnectionLostHandler = func(client mqtt.Client, err error) {
	fmt.Printf("Connection lost : %v\n", err)
	termChan <- struct{}{}
	//fmt.Println("Signalled termChan")
	//client.Disconnect(10)
}

func getCommand() string {
	command := os.Getenv("BERRY_COMMAND")
	if command == "RUN" || command == "SAVE" {
		return command
	}
	fmt.Println("Environment variable BERRY_COMMAND should be set to either RUN or SAVE")
	os.Exit(1)
	return ""
}

func getScript() (filename string, data []byte) {
	fileName := os.Getenv("BERRY_FILENAME")
	if fileName == "" {
		fmt.Println("BERRY_FILENAME environment var is missing")
		//return "", nil
		os.Exit(1)
	}
	var scriptBytes []byte
	var err error
	scriptBytes, err = os.ReadFile(fileName)
	if err != nil {
		fmt.Print("Cannot open file ", err)
		//return fileName, nil
		os.Exit(1)
	}
	if len(bytes.TrimSpace(scriptBytes)) == 0 {
		fmt.Print("The file is empty ", err)
		//return fileName, nil
		os.Exit(1)
	}
	return fileName, scriptBytes
}

func Chunks(s string, chunkSize int) []string {
	if len(s) == 0 {
		return nil
	}
	if chunkSize >= len(s) {
		return []string{s}
	}
	var chunks []string = make([]string, 0, (len(s)-1)/chunkSize+1)
	currentLen := 0
	currentStart := 0
	for i := range s {
		if currentLen == chunkSize {
			chunks = append(chunks, s[currentStart:i])
			currentLen = 0
			currentStart = i
		}
		currentLen++
	}
	chunks = append(chunks, s[currentStart:])
	return chunks
}

func crc(b []byte) uint32 {
	hash := crc32.NewIEEE()
	hash.Write(b)
	return hash.Sum32()
}

func upload_tcp() {
	fileName, data := getScript()
	command := getCommand()
	tcpserver := os.Getenv("TCP_SERVER")
	if tcpserver == "" {
		fmt.Println("TCP_SERVER environment var is missing")
		return
	}
	conn, err := net.Dial("tcp", tcpserver)
	if err != nil {
		println("Connecting to server failed", err.Error())
		os.Exit(1)
	}
	go func() {
		defer func() {
			termChan <- struct{}{}
		}()
		buf := make([]byte, 256)
		tmp := make([]byte, 256)
		state := 1
		for {
			n, err := conn.Read(tmp)
			if err != nil {
				if err != io.EOF {
					fmt.Println("Error reading from remote module :", err)
					return
				}
				break
			}
			if state == 1 {
				if string(tmp[:n]) == "HEADER OK" {
					contChan <- struct{}{}
					state = 2
					fmt.Println("Server responded")
				} else {
					fmt.Printf("Unexpected data %q", string(tmp[:n]))
					return
				}
			} else if state == 2 {
				buf = append(buf, tmp[:n]...)
			} else {
				fmt.Println("Progrmming error")
			}
			/* if len(buf) >= 7 && string(buf[len(buf)-7:]) == "SUCCESS" {
				buf = buf[:len(buf)-7]
				success = true
				break
			} else if len(buf) >= 5 && string(buf[len(buf)-7:]) == "ERROR" {
				buf = buf[:len(buf)-5]
				break
			}*/
			//}
		}
		fmt.Print(string(buf))
		if len(buf) > 0 && buf[len(buf)-1] != '\n' {
			fmt.Println()
		}
		/* if success {
			fmt.Println("Operation completed succesfully")
		} else {
			fmt.Print("Operation failed")
		}*/
	}()
	if command == "RUN" {
		if _, err := fmt.Fprintf(conn, "CR%06X%08X", len(data), crc(data)); err != nil {
			fmt.Println("Cannot send the header to the remote module")
			return
		}
	} else if command == "SAVE" {
		if _, err := fmt.Fprintf(conn, "CS%06X%08X%s", len(data), crc(data), fileName); err != nil {
			fmt.Println("Cannot send the header to the remote module")
			return
		}
	}
	<-contChan
	//
	if _, err := conn.Write(data); err != nil {
		fmt.Println("Cannot send the file to the remote module")
		return
	}
}

func upload_mqtt() {
	fileName, data := getScript()
	command := getCommand()
	mqttserver := os.Getenv("MQTT_SERVER")
	if mqttserver == "" {
		fmt.Println("MQTT_SERVER is missing")
		termChan <- struct{}{}
		return
	}
	username := os.Getenv("MQTT_USERNAME")
	password := os.Getenv("MQTT_PASSWORD")

	mqtt_topic := os.Getenv("MQTT_TOPIC")
	if mqtt_topic == "" {
		fmt.Println("MQTT_TOPIC is missing")
		termChan <- struct{}{}
		return
	}
	publishTopic := "mqttberry/" + mqtt_topic + "/upload"
	subscribeTopic := "mqttberry/" + mqtt_topic + "/report"

	opts := mqtt.NewClientOptions()
	opts.AddBroker(mqttserver)
	opts.SetAutoReconnect(false)
	mqttid := fmt.Sprintf("brupload-%06d", rand.Intn(1_000_000))
	opts.SetClientID(mqttid)
	if username != "" {
		opts.SetUsername(username)
	}
	if password != "" {
		opts.SetPassword(password)
	}
	opts.OnConnect = connectHandler
	opts.OnConnectionLost = connectionLostHandler
	client := mqtt.NewClient(opts)
	if token := client.Connect(); token.Wait() && token.Error() != nil {
		print(token.Error())
		termChan <- struct{}{}
		return
	}
	if token := client.Subscribe(subscribeTopic, 1, rcvMessage); token.Wait() && token.Error() != nil {
		print(token.Error())
		termChan <- struct{}{}
		return
	}
	if command == "RUN" {
		if token := client.Publish(publishTopic, 1, false, fmt.Sprintf("CR%06X%08X", len(data),
			crc(data))); token.Wait() && token.Error() != nil {
			print(token.Error())
			termChan <- struct{}{}
			return
		}
	} else if command == "SAVE" {
		if token := client.Publish(publishTopic, 1, false, fmt.Sprintf("CS%06X%08X%s", len(data),
			crc(data), fileName)); token.Wait() && token.Error() != nil {
			print(token.Error())
			termChan <- struct{}{}
			return
		}
	} else {
		fmt.Printf("Unknown command %q\n", command)
		termChan <- struct{}{}
	}
	<-contChan
	for _, p := range Chunks(string(data), 1000) {
		fmt.Print("*")
		if token := client.Publish(publishTopic, 1, false, p); token.Wait() && token.Error() != nil {
			fmt.Println("\n", token.Error())
			termChan <- struct{}{}
			return
		}
	}
	fmt.Println()
}

func main() {
	upload_mode := os.Getenv("UPLOAD_MODE")
	if upload_mode != "TCP" && upload_mode != "MQTT" {
		fmt.Println("UPLOAD_MODE environment variable must be TCP or MQTT")
		return
	}
	fmt.Println("Using", upload_mode, "upload mode")
	if upload_mode == "TCP" {
		go upload_tcp()
	} else if upload_mode == "MQTT" {
		go upload_mqtt()
	} else {
		fmt.Printf("Error upload mode cannot be %q", upload_mode)
		return
	}
	select {
	case <-termChan:
	case <-time.After(10 * time.Second):
		fmt.Println("Timeout")
	}
}
