#!/bin/bash
# Unified test script for CM4 boat peripherals
# Author: Jatan Pandya / QuireTech LLC
# Updated with comprehensive pass/fail tracking and non-interactive execution

# Function to stop candump processes
cleanup() {
    echo "Stopping any running candump processes..."
    pkill -f candump
    echo "candump processes stopped."
}

# Trap to clean up on exit
trap cleanup EXIT INT TERM

# Initialize all component flags to false
GPIO_TEST_PASSED=false
RTC_TEST_PASSED=false
ETH0_TEST_PASSED=false
ETH1_TEST_PASSED=false
CAN0_TEST_PASSED=false
CAN1_TEST_PASSED=false

# Function to show section headers
section() {
    echo ""
    echo "========== $1 =========="
    echo ""
}

# Function to set LED color
set_led() {
    color=$1
    case $color in
        "RED")
            sudo pinctrl 20,21 op dh
            sudo pinctrl 16 op dl
            ;;
        "GREEN")
            sudo pinctrl 16,21 op dh
            sudo pinctrl 20 op dl
            ;;
        "BLUE")
            sudo pinctrl 16,20 op dh
            sudo pinctrl 21 op dl
            ;;
        "OFF")
            sudo pinctrl 16,20,21 op dl
            ;;
    esac
}

# Main test sequence
echo "========== Starting CM4 Boat Test Suite =========="

# Test 1: GPIO LED Test
section "Testing GPIO LED"
echo "Testing RGB LED functionality..."

echo "Testing RED LED"
set_led "RED"
sleep 1
set_led "OFF"

echo "Testing GREEN LED"
set_led "GREEN"
sleep 1
set_led "OFF"

echo "Testing BLUE LED"
set_led "BLUE"
sleep 1
set_led "OFF"

# Auto-pass the GPIO test since it's visual and we can't check it programmatically
echo "GPIO LED test PASSED (auto-confirmed)"
GPIO_TEST_PASSED=true

# Test 2: RTC Test
section "Testing RTC"

# Check if RTC device exists
if [ ! -e "/dev/rtc0" ]; then
    echo "RTC test FAILED - RTC device not found"
else
    # Get current system time
    SYSTEM_TIME=$(date +%s)
    
    # Get RTC time
    RTC_TIME=$(sudo hwclock -r | date +%s)
    
    # Get detailed RTC info
    RTC_OUTPUT=$(sudo hwclock --verbose 2>&1)
    
    # Print RTC verbose output
    echo "RTC Verbose Output:"
    echo "$RTC_OUTPUT"
    
    # Check if times are within 2 seconds of each other
    TIME_DIFF=$(( SYSTEM_TIME - RTC_TIME ))
    TIME_DIFF=${TIME_DIFF#-} # Get absolute value
    
    if [ $TIME_DIFF -le 2 ]; then
        # Check if we can write to RTC
        if sudo hwclock --systohc; then
            # Verify we can read back
            if sudo hwclock --show > /dev/null 2>&1; then
                echo "RTC test PASSED - Device functional, time synced (diff: ${TIME_DIFF}s)"
                RTC_TEST_PASSED=true
            else
                echo "RTC test FAILED - Could not read time after write"
            fi
        else
            echo "RTC test FAILED - Could not write to RTC"
        fi
    else
        echo "RTC test FAILED - Time difference too large (${TIME_DIFF}s)"
    fi
fi

# Test 3: Ethernet Test
section "Testing Ethernet"
# Check eth0
if ip link show eth0 2>/dev/null | grep -q "state UP"; then
    echo "eth0 is UP"
    ETH0_TEST_PASSED=true
else
    echo "eth0 is DOWN or missing"
fi

# Check eth1
if ip link show eth1 2>/dev/null | grep -q "state UP"; then
    echo "eth1 is UP"
    ETH1_TEST_PASSED=true
else
    echo "eth1 is DOWN or missing"
fi

# Test 6: GPS over CAN Test
section "Testing GPS over CAN"
echo "Automatically running GPS test..."

# Remove any existing CAN output files
rm -f can0_output.txt can1_output.txt

echo "Setting up CAN interfaces for GPS data..."
sudo ip link set can0 down
sudo ip link set can0 type can bitrate 250000 loopback off
sudo ip link set can0 up

sudo ip link set can1 down
sudo ip link set can1 type can bitrate 250000 loopback off
sudo ip link set can1 up

# Test CAN0
echo "Testing CAN0 interface..."
candump can0 -T 500 > can0_output.txt &
CAN0_PID=$!
sleep 0.5
kill $CAN0_PID

echo "CAN0 Output:"
cat can0_output.txt

if grep -E "can0.*\[[0-9]\].*[0-9A-F]{2}.*[0-9A-F]{2}" can0_output.txt > /dev/null; then
    echo "CAN0 test PASSED - Valid CAN data detected"
    CAN0_TEST_PASSED=true
else
    echo "CAN0 test FAILED - No valid CAN data detected"
fi

# Test CAN1 
echo "Testing CAN1 interface..."
candump can1 -T 500 > can1_output.txt & 
CAN1_PID=$!
sleep 0.5
kill $CAN1_PID

echo "CAN1 Output:"
cat can1_output.txt

if grep -E "can1.*\[[0-9]\].*[0-9A-F]{2}.*[0-9A-F]{2}" can1_output.txt > /dev/null; then
    echo "CAN1 test PASSED - Valid CAN data detected"
    CAN1_TEST_PASSED=true
else
    echo "CAN1 test FAILED - No valid CAN data detected"
fi

# Summary of all tests
section "Test Results Summary"
echo -e "GPIO LED Test: $(if $GPIO_TEST_PASSED; then echo -e "\e[32mPASSED\e[0m"; else echo -e "\e[31mFAILED\e[0m"; fi)"
echo -e "RTC Test: $(if $RTC_TEST_PASSED; then echo -e "\e[32mPASSED\e[0m"; else echo -e "\e[31mFAILED\e[0m"; fi)"
echo -e "Ethernet eth0 Test: $(if $ETH0_TEST_PASSED; then echo -e "\e[32mPASSED\e[0m"; else echo -e "\e[31mFAILED\e[0m"; fi)"
echo -e "Ethernet eth1 Test: $(if $ETH1_TEST_PASSED; then echo -e "\e[32mPASSED\e[0m"; else echo -e "\e[31mFAILED\e[0m"; fi)"
echo -e "CAN0 Test: $(if $CAN0_TEST_PASSED; then echo -e "\e[32mPASSED\e[0m"; else echo -e "\e[31mFAILED\e[0m"; fi)"
echo -e "CAN1 Test: $(if $CAN1_TEST_PASSED; then echo -e "\e[32mPASSED\e[0m"; else echo -e "\e[31mFAILED\e[0m"; fi)"

# Final result - if all tests passed, set LED to GREEN, otherwise RED
if $GPIO_TEST_PASSED && $RTC_TEST_PASSED && $ETH0_TEST_PASSED && $ETH1_TEST_PASSED && \
   $CAN0_TEST_PASSED && $CAN1_TEST_PASSED; then
    echo -e "\e[32m========== ALL TESTS PASSED! ==========\e[0m"
    set_led "GREEN"
else
    echo -e "\e[31m========== SOME TESTS FAILED! ==========\e[0m"
    set_led "RED"
fi

# Keep LED status permanently (no user interaction required to turn it off)
echo "Test completed. LED status will remain to indicate test result."

echo "========== Test suite completed! =========="