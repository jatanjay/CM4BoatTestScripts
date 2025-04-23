#!/bin/bash
# auth: jatan pandya / quiretech llc


echo ""
# test gpio
echo "\033[1;33m Testing GPIO\033[0m"
sh test_scripts/test_gpio_led.sh
echo "\033[1;32mDone!\033[0m"

echo ""
echo ""


# test wifi
echo "\033[1;33m Testing WiFi\033[0m"
sh test_scripts/test_wifi.sh
echo "\033[1;32mDone!\033[0m"

echo ""
echo ""


# test rtc
echo "\033[1;33m Testing RTC\033[0m"
sh test_scripts/test_rtc.sh
echo "\033[1;32mDone!\033[0m"


echo ""
echo ""

# test can
echo "\033[1;33m Testing CAN\033[0m"
sh test_scripts/test_can.sh
echo "\033[1;32mDone!\033[0m"

echo ""
echo ""

# test can gps
echo "\033[1;33m Testing CAN w/ GPS\033[0m"
sh test_scripts/can_gps_test.sh
echo "\033[1;32mDone!\033[0m"

echo ""
echo ""

# test eth
echo "\033[1;33m Testing Ethernet (eth1, eth2) \033[0m"
sh test_scripts/test_eth.sh
echo "\033[1;32mDone!\033[0m"


