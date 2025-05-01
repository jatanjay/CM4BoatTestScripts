#!/bin/bash

# Check if IP address is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <ip_address>"
    echo "Example: $0 192.168.1.100"
    exit 1
fi

IP_ADDRESS=$1
USERNAME="viam"
PASSWORD="checkmate"
TEST_SCRIPT="./test/all_test.sh"

# Check if sshpass is installed
if ! command -v sshpass &> /dev/null; then
    echo "sshpass is not installed. Installing..."
    apt-get update
    apt-get install -y sshpass
fi

echo "Connecting to $IP_ADDRESS and running test script..."
echo "----------------------------------------"

# SSH into the device and run the test script
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USERNAME@$IP_ADDRESS" "$TEST_SCRIPT" 