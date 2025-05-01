#!/bin/bash
# auth: jatan pandya / quiretech llc

echo "\033[1;33m ----------- Update dt-overlays, configs for RPI\033[0m -----------"

# Set up I2C
echo "  Running I2C setup"
sh setup_scripts/setup_i2c.sh
echo "\033[1;32mDone!\033[0m"

# Set up RTC
echo "  Running RTC setup"
sh setup_scripts/setup_rtc.sh
echo "\033[1;32mDone!\033[0m"

# Set up CAN configuration
echo "  Running CAN configuration setup"
sh setup_scripts/setup_can.sh
echo "\033[1;32mDone!\033[0m"

# Reboot the system to apply all changes
echo "\033[1;33m  Rebooting the system to apply all changes\033[0m -----------"
#sh reboot_rpi.sh
