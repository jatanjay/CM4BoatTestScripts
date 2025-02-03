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

    # Prompt user to enter Wi-Fi credentials
    read -p "Please enter the SSID of the Wi-Fi network: " user_ssid
    read -sp "Please enter the password for $user_ssid: " user_password
    echo


    echo "network={" >> /etc/wpa_supplicant/wpa_supplicant.conf
    echo "    ssid=\"$user_ssid\"" >> /etc/wpa_supplicant/wpa_supplicant.conf
    echo "    psk=\"$user_password\"" >> /etc/wpa_supplicant/wpa_supplicant.conf
    echo "}" >> /etc/wpa_supplicant/wpa_supplicant.conf

    echo "Wi-Fi credentials have been saved. Attempting to connect..."
    sudo systemctl restart networking

    echo "Wi-Fi credentials saved and the Raspberry Pi is attempting to connect to $user_ssid."
fi
