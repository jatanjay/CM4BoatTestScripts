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
TEST_DIR="./test"
TEST_SCRIPT="all_test.sh"

# Check if test directory exists locally
if [ ! -d "$TEST_DIR" ]; then
    echo "Error: Test directory $TEST_DIR not found"
    exit 1
fi

# Run test script twice
for i in 1 2; do
    echo "Running test iteration $i..."
    echo "Copying test directory to $IP_ADDRESS and running tests..."
    echo "----------------------------------------"

    # Copy the test directory recursively to remote device
    sshpass -p "$PASSWORD" scp -r -o StrictHostKeyChecking=no "$TEST_DIR" "$USERNAME@$IP_ADDRESS:/home/$USERNAME/"

    # Verify directory was copied successfully
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USERNAME@$IP_ADDRESS" "[ -d /home/$USERNAME/test ]" || {
        echo "Error: Failed to copy test directory to remote device"
        exit 1
    }

    # Convert line endings and make script executable
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USERNAME@$IP_ADDRESS" "find /home/$USERNAME/test -type f -exec dos2unix {} \; && chmod +x /home/$USERNAME/test/$TEST_SCRIPT"

    # SSH into the device and run the test script
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USERNAME@$IP_ADDRESS" "/home/$USERNAME/test/$TEST_SCRIPT"

    # Add a separator between iterations
    if [ $i -eq 1 ]; then
        echo ""
        echo "========== First iteration complete, starting second run =========="
        echo ""
    fi
done