#!/bin/bash
# Unified setup script for CM4 boat peripherals
# Author: Jatan Pandya / QuireTech LLC
# Updated for non-interactive operation

# Configuration options
AUTO_REBOOT=true  # Set to false to disable automatic reboot
LOG_FILE="/var/log/cm4boat_setup.log"

# Function to log setup steps
log_setup() {
    local step=$1
    local message=$2
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $step: $message" | tee -a $LOG_FILE
}

# Start setup process
echo "========== Setting up all peripherals for CM4 Boat ==========" | tee -a $LOG_FILE
log_setup "SETUP" "Starting CM4 boat peripherals setup"

# Create log file
touch $LOG_FILE
log_setup "LOG" "Created log file at $LOG_FILE"

# Set up CAN bus
log_setup "CAN" "Setting up CAN interfaces"
grep -qxF 'dtparam=spi=on' /boot/firmware/config.txt || echo 'dtparam=spi=on' | sudo tee -a /boot/firmware/config.txt
grep -qxF 'dtoverlay=mcp2515-can0,oscillator=12000000,interrupt=25,spimaxfrequency=2000000' /boot/firmware/config.txt || echo 'dtoverlay=mcp2515-can0,oscillator=12000000,interrupt=25,spimaxfrequency=2000000' | sudo tee -a /boot/firmware/config.txt
grep -qxF 'dtoverlay=mcp2515-can1,oscillator=12000000,interrupt=24,spimaxfrequency=2000000' /boot/firmware/config.txt || echo 'dtoverlay=mcp2515-can1,oscillator=12000000,interrupt=24,spimaxfrequency=2000000' | sudo tee -a /boot/firmware/config.txt
grep -qxF 'can' /etc/modules || echo 'can' | sudo tee -a /etc/modules
log_setup "CAN" "CAN interface configuration completed"

# Install CAN utilities if not already installed
if ! dpkg -l | grep -q 'can-utils'; then
  log_setup "CAN" "can-utils not found, installing..."
  sudo apt-get update
  sudo apt-get install -y can-utils
  log_setup "CAN" "can-utils installed successfully"
else
  log_setup "CAN" "can-utils is already installed"
fi

# Set up I2C
log_setup "I2C" "Setting up I2C interfaces"
sudo raspi-config nonint do_i2c 0
sudo modprobe i2c-dev
sudo modprobe i2c-bcm2708
grep -qxF 'i2c-dev' /etc/modules || echo 'i2c-dev' | sudo tee -a /etc/modules
grep -qxF 'i2c-bcm2708' /etc/modules || echo 'i2c-bcm2708' | sudo tee -a /etc/modules
grep -qxF 'dtparam=i2c_arm=on' /boot/firmware/config.txt || echo 'dtparam=i2c_arm=on' | sudo tee -a /boot/firmware/config.txt
log_setup "I2C" "I2C configuration completed"

# Set up RTC
log_setup "RTC" "Setting up RTC module"
grep -qxF 'dtoverlay=i2c-rtc,pcf85063a,i2c_csi_dsi,addr=0x51' /boot/firmware/config.txt || echo 'dtoverlay=i2c-rtc,pcf85063a,i2c_csi_dsi,addr=0x51' | sudo tee -a /boot/firmware/config.txt
log_setup "RTC" "RTC configuration completed"

# Set up UART for GPS
log_setup "UART" "Setting up UART for GPS"
grep -qxF 'enable_uart=1' /boot/firmware/config.txt || echo 'enable_uart=1' | sudo tee -a /boot/firmware/config.txt
grep -qxF 'dtoverlay=uart1' /boot/firmware/config.txt || echo 'dtoverlay=uart1' | sudo tee -a /boot/firmware/config.txt
log_setup "UART" "UART configuration completed"


echo "========== Setup completed! ==========" | tee -a $LOG_FILE
log_setup "SETUP" "All peripherals have been configured"

# Handle reboot
if [ "$AUTO_REBOOT" = true ]; then
  log_setup "REBOOT" "Automatic reboot initiated"
  echo "System will reboot in 5 seconds to apply all changes..." | tee -a $LOG_FILE
  echo "Press Ctrl+C to cancel reboot" | tee -a $LOG_FILE
  sleep 5
  sudo reboot
else
  log_setup "REBOOT" "Automatic reboot disabled"
  echo "Please reboot the system manually when convenient." | tee -a $LOG_FILE
  echo "sudo reboot" | tee -a $LOG_FILE
fi 