#!/bin/bash
# auth: jatan pandya

wifi_info=$(iwconfig wlan0)

if echo "$wifi_info" | grep -q "ESSID"; then
    echo "The Raspberry Pi is connected to a Wi-Fi network."

    ssid=$(echo "$wifi_info" | grep -oP 'ESSID:"\K[^"]+')
    signal_strength=$(echo "$wifi_info" | grep -oP 'Signal level=\K[-0-9]+')

    echo "Connected to SSID: $ssid"
    echo "Signal Strength: $signal_strength dBm"

else
    echo "The Raspberry Pi is not connected to Wi-Fi."
fi
