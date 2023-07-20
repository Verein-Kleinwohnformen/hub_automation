#!/bin/bash
# This script is intended to be run on a EdgeBox-RPI-200 running Raspbian
# It will install the E-Monitor software and configure the system
# It will also update the system and upgrade it to the latest version of Raspbian
echo -e "Starting the E-Monitor installation script.\nThis script will install E-Monitor, update the system, upgrade to the latest Raspbian, and perform multiple reboots.\nPlease be patient as the script continues to run after each reboot until completion."


FIRSTSTART_MARKER=/usr/local/pi/firststart.marker

if [ ! -f $FIRSTSTART_MARKER ]; then
    # The file does not exist, so we'll do the first start stuff here

    # Copy script to /var/run/pi no matter from where is started
    sudo mkdir -p /usr/local/pi
    sudo cp -f ./install.sh /usr/local/pi/install.sh

    # Define the script path and service name
    SCRIPT_PATH="/usr/local/pi/install.sh"
    SERVICE_NAME="installPi"

    # Create the service file
    echo "[Unit]
    Description=Automatet Install for E-Monitor Setup

    [Service]
    ExecStart=$SCRIPT_PATH

    [Install]
    WantedBy=multi-user.target" | sudo tee /etc/systemd/system/$SERVICE_NAME.service > /dev/null

    # Give your script execute permissions
    sudo chmod +x $SCRIPT_PATH

    # Reload the systemd daemon
    sudo systemctl daemon-reload

    # Enable the service so that it starts on boot
    sudo systemctl enable $SERVICE_NAME.service

    # Start the service
    sudo systemctl start $SERVICE_NAME.service

    # Update OS and all packages
    sudo apt-get update -yqq
    sudo apt-get upgrade -yqq
    sudo apt-get dist-upgrade -yqq

    # Cleanup unused packages
    sudo apt-get autoremove -yqq
    sudo apt-get autoclean -yqq

    # Create the first start marker file
    sudo touch $FIRSTSTART_MARKER
    sudo reboot
else
    # The file exists, so the first start has already been done

    #Continue with the rest of the script
    echo "The system has been setup for start and the system rebooted."

UPGRADE_MARKER=/usr/local/pi/upgrade.marker

# Check if the upgrade marker file exists
if [ ! -f $UPGRADE_MARKER ]; then
  # The file does not exist, so we'll do the upgrade

  # Switch the OS sources from 'buster' to 'bullseye'
  sudo sed -i 's/buster/bullseye/g' /etc/apt/sources.list
  sudo sed -i 's/buster/bullseye/g' /etc/apt/sources.list.d/raspi.list

  # Update and upgrade the system
  sudo apt-get update -yqq
  sudo apt-get upgrade -yqq
  sudo apt-get dist-upgrade -yqq

  # Create the upgrade marker file
  sudo touch $UPGRADE_MARKER

  # Reboot the system
  sudo reboot
else
  # The file exists, so the upgrade has already been done

  # Continue with the rest of the script
  echo "The system has been upgraded and the system rebooted."
fi

HARDWARE_MARKER=/usr/local/pi/hardware.marker

#Check if the hardware marker file exists
if [ ! -f $HARDWARE_MARKER ]; then
    # The file does not exist, so we'll do the hardware setup
    # Activate RTC
    echo "dtoverlay=i2c-rtc,pcf8563" | sudo tee -a /boot/config.txt

    # Export GPIO pins 6 and 5
    echo 6 | sudo tee /sys/class/gpio/export > /dev/null
    echo 5 | sudo tee /sys/class/gpio/export > /dev/null

    # Set GPIO 6 as output
    echo out | sudo tee /sys/class/gpio/gpio6/direction > /dev/null

    # Set the value of GPIO 6 to 1
    echo 1 | sudo tee /sys/class/gpio/gpio6/value > /dev/null

    # Set GPIO 5 as output
    echo out | sudo tee /sys/class/gpio/gpio5/direction > /dev/null

    # Set the value of GPIO 5 to 1
    echo 1 | sudo tee /sys/class/gpio/gpio5/value > /dev/null

    # Create the hardware marker file
    sudo touch $HARDWARE_MARKER

    # Reboot the system
    sudo reboot
else
    # The file exists, so the hardware setup has already been done

    # Continue with the rest of the script
    echo "The hardware has been setup and the system rebooted."
fi

PACKAGE_MARKER=/usr/local/pi/packages.marker

#Check if the package marker file exists
if [ ! -f $PACKAGE_MARKER ]; then

    # Install the required packages

    # Basic packages
    sudo apt install -yqq git curl wget python3-pip 

    # Install packages for IoT Edge 1.4
    curl https://packages.microsoft.com/config/debian/11/packages-microsoft-prod.deb > ./packages-microsoft-prod.deb
    sudo apt install ./packages-microsoft-prod.deb
    sudo apt update -yqq
    sudo apt install moby-engine moby-cli -yqq

    # Install packages für GPIO to docker
    sudo apt install -yqq pigpiod python3-pigpio python3-pigpio

    # Install packages for LTE Module
	sudo apt install minicom -y
    sudo apt install expect -y

    # Install packages for Wifi AP Mode
    sudo apt install -yqq hostapd dnsmasq
    
    # Create the hardware marker file
    sudo touch $PACKAGE_MARKER

    # Reboot the system
    sudo reboot
else
    # The file exists, so the hardware setup has already been done

    # Continue with the rest of the script
    echo "The Software has been setup and the system rebooted."
fi

CONFIGURATION_MARKER=/usr/local/pi/configuration.marker

# Check if the configuration marker file exists
if [ ! $CONFIGURATION_MARKER ]; then
    # The file does not exist, so we'll do the configuration

    # Configure the system
    # Configure LTE for Quectel EC25-E
    cat <<EOF > minicom_script.exp
    #!/usr/bin/expect

    spawn minicom -D /dev/ttyUSB3 -b 115200

    expect "Welcome to minicom"

    send "AT\r"
    expect {
    "OK" { puts "AT - Response: OK" }
    timeout { puts "AT - Response: Timeout" }
    }

    send "AT+QCFG=\"usbnet\",1\r"
    expect {
    "OK" { puts "AT+QCFG=\"usbnet\",1 - Response: OK" }
    timeout { puts "AT+QCFG=\"usbnet\",1 - Response: Timeout" }
    }

    send "AT+CGDCONT=1,\"IP\",\"dr.m2m.ch\"\r"
    expect {
    "OK" { puts "AT+CGDCONT=1,\"IP\",\"dr.m2m.ch\" - Response: OK" }
    timeout { puts "AT+CGDCONT=1,\"IP\",\"dr.m2m.ch\" - Response: Timeout" }
    }

    send "AT+CFUN=1,1\r"
    expect {
    "OK" { puts "AT+CFUN=1,1 - Response: OK" }
    timeout { puts "AT+CFUN=1,1 - Response: Timeout" }
    }

    interact
EOF

	expect minicom_script.exp

    # Configure Interface for lte0
    vendor_id=$(lsusb | grep "Quectel EC25" | awk '{print $6}' | cut -d ":" -f 1)
    product_id=$(lsusb | grep "Quectel EC25" | awk '{print $6}' | cut -d ":" -f 2)

    if [[ -z $vendor_id ]] || [[ -z $product_id ]]; then
    echo "Failed to find the vendor and product IDs of the Quectel EC25 modem."
    exit 1
    fi

    sudo tee /etc/udev/rules.d/10-quectel-interface.rules > /dev/null << EOF
    SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="$vendor_id", ATTRS{idProduct}=="$product_id", NAME="myinterface"
EOF

    sudo udevadm control --reload-rules

    # Configure Wifi AP Mode

    # Configure GPIO to docker

    # Configure IoT Edge 1.4
	echo '{
		"log-driver": "local",
		"dns": ["8.8.8.8"]
	}' | sudo tee /etc/docker/daemon.json > /dev/null

	systemctl restart docker 

    # Create the configuration marker file
    sudo touch $CONFIGURATION_MARKER

    # Reboot the system
    sudo reboot
else
    # The file exists, so the configuration has already been done

    # Continue with the rest of the script
    echo "The Packages has been configured and the system rebooted."
fi

CRONETAB_MARKER=/usr/local/pi/crontab.marker

# Check if the crontab marker file exists
if [ ! $CRONETAB_MARKER ]; then
    # The file does not exist, so we'll do the crontab setup

    # Definieren Sie den Pfad, unter dem das Update-Skript erstellt werden soll.
    UPDATE_SCRIPT_PATH="/usr/local/pi/crone/"
    UPDATE_SCRIPT_FILE=$UPDATE_SCRIPT_PATH + "update.sh"

    # Erstellen Sie das Verzeichnis, in dem das Update-Skript gespeichert werden soll.
    mkdir -p $(dirname $UPDATE_SCRIPT_PATH)
    
    # Erstelle das Update-Skript und schreibe den Inhalt hinein.
    cat << EOF > $UPDATE_SCRIPT_FILE
    #!/bin/bash
    sudo apt update -yqq
    sudo apt upgrade -yqq
EOF

    # Setze die Ausführungsberechtigungen für das Update-Skript.
    chmod +x $UPDATE_SCRIPT_FILE

    # Erstelle den Cron-Job, der das Skript einmal im Monat ausführt.
    # Die 'crontab' -Befehle verwenden den '-l' Schalter, um die aktuelle Crontab zu listen,
    # und 'echo' um die neue Zeile hinzuzufügen, die den neuen Job definiert.
    # Dann wird der gesamte Ausdruck in 'crontab' gepiped, um die neue Crontab zu erstellen.
    (crontab -l; echo "0 0 1 * * $UPDATE_SCRIPT_FILE") | sudo crontab -

    echo "Update script created at $UPDATE_SCRIPT_FILE"
    echo "Cron job created. It will run $UPDATE_SCRIPT_FILE on the first day of each month."

    # Create the crontab marker file
    sudo touch $CRONETAB_MARKER

    # Reboot the system
    sudo reboot
else
    # The file exists, so the crontab setup has already been done

    # Continue with the rest of the script
    echo "The crontab has been configured and the system rebooted."
fi

SSD_MARKER=/usr/local/pi/ssd.marker

# Check if the SSD marker file exists
if [ ! $SSD_MARKER ]; then
    # The file does not exist, so we'll do the SSD setup

    # Change Bootorder to nvme
	sudo apt install git libusb-1.0-0-dev build-essential -y
	git clone --depth=1 https://github.com/raspberrypi/usbboot
	cd usbboot
	make
	cd usbboot/recovery
	#download the latest stable firmware & update
	curl -L -o pieeprom.original.bin https://github.com/raspberrypi/rpi-eeprom/raw/master/firmware/stable/pieeprom-2022-05-11.bin
	./update-pieeprom.sh
	sudo sed -i 's/BOOT_ORDER=0xf25641/BOOT_ORDER=0xf25416/' boot.conf
    ./update-pieeprom.sh
	
    # Create the SSD marker file
    sudo touch $SSD_MARKER

    # Copy entire system to nvme
	sudo dd if=/dev/mmcblk0 of=/dev/nvme0n1 bs=4MB status=progress

    # Reboot the system
    sudo reboot
	
	# Resize the partition
    sudo parted /dev/nvme0n1 resizepart 2 100%

    # Resize the filesystem
    sudo resize2fs /dev/nvme0n1p2
	
	# Reboot the system
	sudo reboot
else
    # The file exists, so the SSD setup has already been done
	# Check if booted from SSD or EEPROM
	device=$(lsblk -no pkname /dev/nvme0n1p1)  # Assuming the root partition is on /dev/nvme0n1p1

	if [[ $device == "nvme0n1" ]]; then
		echo "Booted from SSD"
	elif [[ $device == "mmcblk0" ]]; then
		echo "Booted from EEPROM"
	else
		echo "Unknown boot device"
	fi

    # Continue with the rest of the script
    echo "The SSD has been configured and the system bootet on SSD."
fi

# End of the script
echo "The start script has completed."






