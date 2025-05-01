#!/bin/bash

# Check if eth0 and eth1 are up
if ip link show eth0 | grep -q "state UP" && ip link show eth1 | grep -q "state UP"; then
    echo "Ethernet check passed"
else
    echo "Ethernet check failed"
fi
