#!/bin/bash
# auth: jatan pandya / quiretech llc

echo "Setting up CAN interface (can0)..."
sudo ip link set can0 down
sudo ip link set can0 type can bitrate 1000000 loopback on
sudo ip link set can0 up type can bitrate 1000000

echo "CAN interface can0 is configured with loopback enabled."

echo "Starting candump on can0..."
candump can0 &

sleep 2

echo "Sending test message to can0... (11.22.33.44)"
cansend can0 000#11.22.33.44
echo "Check the output below for the test message sent from can0. Should match '11 22 33 44' "

