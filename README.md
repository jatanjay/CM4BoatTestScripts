# RPI-CM4 Based Boat Monitoring Unit

The **Boat Monitoring Unit** is a custom device based on the Raspberry Pi Compute Module 4 (RPI CM4), designed to monitor and control various hardware interfaces. This unit integrates functionalities like CAN bus, I2C, LEDs, RTC (Real-Time Clock), Wi-Fi, and Ethernet. The repository provides a collection of setup and test scripts to configure and validate these hardware interfaces.

These scripts were developed to automate QA testing on 250 units developed by **QuireTech LLC**.

The scripts included in this repository allow for enabling and testing the following functionalities:

## CAN Bus

- Ensures the `spi=on` parameter is set in the `/boot/firmware/config.txt` file.
- Configures the MCP2515 CAN controller overlay with specific settings for the oscillator, interrupt, and SPI frequency.
- Adds the `can` module to `/etc/modules` if not already present.
- Installs the `can-utils` package if it isn't already installed (useful for CAN bus interaction).

## I2C

- Loads the necessary `i2c-dev` and `i2c-bcm2708` kernel modules.
- Adds both modules to `/etc/modules` if they aren't already present.
- Enables the `i2c_arm=on` parameter in `/boot/firmware/config.txt`.

## RTC (Real-Time Clock)

- Ensures the `dtoverlay=i2c-rtc,pcf85063a,i2c_csi_dsi,addr=0x51` overlay is set in the `/boot/firmware/config.txt` file to enable the RTC module.

## Wi-Fi Status

- Uses `iwconfig`

## GPIO LED Control

- Uses `pinctrl`

## Usage:

- `sudo sh ./setup_configs.sh` Will edit all config.txt, overlays etc. It will reboot once done.
- `sudo sh ./test_all.sh` Test out all peripherals

# Further Explanation

## 1. CAN Interface Setup and Test

### Description

This script configures and tests the CAN bus interface (`can0`) on the Raspberry Pi. It sets up the MCP2515 CAN controller and verifies its functionality by sending a test message.

### Steps

1. **Configure CAN Interface**:

   - Brings down the `can0` interface.
   - Sets the bitrate to 1 Mbps (1000000 bps).
   - Enables loopback mode for testing purposes.

2. **Start `candump`**:

   - Starts listening on the `can0` interface to capture and display any incoming CAN messages.

3. **Send Test Message**:
   - Sends a test CAN message (`11.22.33.44`) to verify the CAN interface is functioning correctly.

## 2. GPIO LED Test

### Description

This script is used to test an RGB LED connected to GPIO pins on the Raspberry Pi. It sequentially activates red, green, blue, and white colors to ensure the LED is functioning properly.

### Steps

1. **Control LED Colors**:

   - The script controls the GPIO pins to set each LED color (Red, Green, Blue, White) to high or low states, turning them on or off as needed.

2. **Sequential Testing**:
   - The colors are displayed one after the other to verify the full range of LED functionality.
   - HI/LO states can be tweaked or combined to create secondary colors.

## 3. Hardware Clock Check

### Description

This script checks the status and configuration of the hardware clock (RTC). It displays the current time and details about the RTC configuration.

### Steps

1. **Display Hardware Clock Information**:
   - Uses the `hwclock --verbose` command to display detailed information about the RTC, including the current time and its settings.
   - For a more comprehensive usage, refer to github [repo](https://github.com/barthm1/rpi-pcf85063/blob/main/pcf85063.py)

## 4. Wi-Fi Connection Info

### Description

This script checks if the Raspberry Pi is connected to a Wi-Fi network and displays the SSID (network name) and signal strength if connected.

### Steps

1. **Check Wi-Fi Status**:

   - Uses `iwconfig` to check the Wi-Fi status and extract the SSID and signal strength.

2. **Display Wi-Fi Information**:
   - If connected, the script displays the current SSID and signal strength.
   - If not connected, the script indicates that no Wi-Fi connection is available.
