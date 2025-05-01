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


echo "Copying test script to $IP_ADDRESS and running it..."
echo "----------------------------------------"

# Copy the test script to remote device
sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no "$TEST_SCRIPT" "$USERNAME@$IP_ADDRESS:/home/$USERNAME/"

# Make the script executable on the remote device
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USERNAME@$IP_ADDRESS" "chmod +x /home/$USERNAME/all_test.sh"

# SSH into the device and run the test script
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USERNAME@$IP_ADDRESS" "/home/$USERNAME/all_test.sh"