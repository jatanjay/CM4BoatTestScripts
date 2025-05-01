#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Check if arp-scan is installed
if ! command -v arp-scan &> /dev/null; then
    echo "arp-scan is not installed. Installing..."
    apt-get update
    apt-get install -y arp-scan
fi

# Get the network interface information
INTERFACE="eth0"
IP_ADDR=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
NETWORK=$(ip -4 route | grep $INTERFACE | grep -v default | awk '{print $1}')

if [ -z "$IP_ADDR" ]; then
    echo "Could not determine IP address for $INTERFACE"
    exit 1
fi

echo "Clearing ARP table..."
ip -s -s neigh flush all

echo "Scanning network $NETWORK for active devices..."
echo "Your IP address: $IP_ADDR"
echo "----------------------------------------"

# Perform the scan using arp-scan
arp-scan --interface=$INTERFACE --localnet | grep -v "Starting" | grep -v "Interface" | grep -v "packets" | while read -r line; do
    if [[ $line =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        IP=$(echo $line | awk '{print $1}')
        MAC=$(echo $line | awk '{print $2}')
        VENDOR=$(echo $line | cut -d' ' -f3-)
        printf "IP: %-15s MAC: %-17s Vendor: %s\n" "$IP" "$MAC" "$VENDOR"
        echo "----------------------------------------"
    fi
done
