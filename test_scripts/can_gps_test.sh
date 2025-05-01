#!/bin/bash
# auth: jatan pandya / quiretech llc

#echo "Setting up CAN interface (can0)..."
#sudo ip link set can0 down
#sudo ip link set can0 type can bitrate 250000 loopback off
#sudo ip link set can0 up type can bitrate 250000

#echo "CAN interface can0 is configured for receveing GPS data"

#echo "Starting candump on can0..."
#candump can0 &

#sleep 2



#echo "Setting up CAN interface (can1)..."
#sudo ip link set can1 down
#sudo ip link set can1 type can bitrate 250000 loopback off
#sudo ip link set can1 up type can bitrate 250000

#echo "CAN interface can1 is configured for receveing GPS data"

#echo "Starting candump on can1..."
#candump can1 &

#sleep 2



#!/bin/bash

# Author: Jatan Pandya / QuireTech LLC

# Function to stop candump processes
cleanup() {
    echo "Stopping candump processes..."
    kill $candump_pid1
    kill $candump_pid2
    echo "candump processes stopped."
    exit 0
}

# Trap to clean up on exit
trap cleanup INT TERM

# Setting up CAN interface (can0)
echo "Setting up CAN interface (can0)..."
sudo ip link set can0 down
sudo ip link set can0 type can bitrate 250000 loopback off
sudo ip link set can0 up type can bitrate 250000

echo "CAN interface can0 is configured for receiving GPS data"

# Start candump on can0 in the background
echo "Starting candump on can0..."
candump can0 &
candump_pid1=$!
echo "candump started on can0 with PID $candump_pid1"

sleep 2

# Setting up CAN interface (can1)
echo "Setting up CAN interface (can1)..."
sudo ip link set can1 down
sudo ip link set can1 type can bitrate 250000 loopback off
sudo ip link set can1 up type can bitrate 250000

echo "CAN interface can1 is configured for receiving GPS data"

# Start candump on can1 in the background
echo "Starting candump on can1..."
candump can1 &
candump_pid2=$!
echo "candump started on can1 with PID $candump_pid2"

# Wait for both background processes to finish
wait $candump_pid1
wait $candump_pid2
