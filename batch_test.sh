#!/bin/bash

USERNAME="viam"
PASSWORD="checkmate"
TEST_DIR="./test"
TEST_SCRIPT="all_test.sh"

# Check if test directory exists locally
if [ ! -d "$TEST_DIR" ]; then
    echo "Error: Test directory $TEST_DIR not found"
    exit 1
fi

# Get list of Raspberry Pi IP addresses from ip_scan.ps
RASPBERRY_PI_IPS=$(powershell.exe -File ip_scan.ps | grep -i "Raspberry Pi Trading Ltd" | awk '{print $1}')

if [ -z "$RASPBERRY_PI_IPS" ]; then
    echo "No Raspberry Pi devices found on the network"
    exit 1
fi

# Process each Raspberry Pi device sequentially
for IP_ADDRESS in $RASPBERRY_PI_IPS; do
    echo "Processing device at IP: $IP_ADDRESS"
    
    # Run test script twice for each device
    for i in 1 2; do
        echo "Running test iteration $i for $IP_ADDRESS..."
        echo "Copying test directory to $IP_ADDRESS and running tests..."
        echo "----------------------------------------"

        # Copy the test directory recursively to remote device
        sshpass -p "$PASSWORD" scp -r -o StrictHostKeyChecking=no "$TEST_DIR" "$USERNAME@$IP_ADDRESS:/home/$USERNAME/"

        # Verify directory was copied successfully
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USERNAME@$IP_ADDRESS" "[ -d /home/$USERNAME/test ]" || {
            echo "Error: Failed to copy test directory to device at $IP_ADDRESS"
            continue
        }

        # Convert line endings and make script executable
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USERNAME@$IP_ADDRESS" "find /home/$USERNAME/test -type f -exec dos2unix {} \; && chmod +x /home/$USERNAME/test/$TEST_SCRIPT"

        # SSH into the device and run the test script
        sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USERNAME@$IP_ADDRESS" "/home/$USERNAME/test/$TEST_SCRIPT"

        # Add a separator between iterations
        if [ $i -eq 1 ]; then
            echo ""
            echo "========== First iteration complete, starting second run for $IP_ADDRESS =========="
            echo ""
        fi
    done

    echo ""
    echo "========== Completed testing device at $IP_ADDRESS =========="
    echo ""
done