#!/bin/bash
# auth: jatan pandya / quiretech llc

grep -qxF 'dtparam=spi=on' /boot/firmware/config.txt || echo 'dtparam=spi=on' | sudo tee -a /boot/firmware/config.txt
grep -qxF 'dtoverlay=mcp2515-can0,oscillator=12000000,interrupt=25,spimaxfrequency=2000000' /boot/firmware/config.txt || echo 'dtoverlay=mcp2515-can0,oscillator=12000000,interrupt=25,spimaxfrequency=2000000' | sudo tee -a /boot/firmware/config.txt
grep -qxF 'dtoverlay=mcp2515-can1,oscillator=12000000,interrupt=24,spimaxfrequency=2000000' /boot/firmware/config.txt || echo 'dtoverlay=mcp2515-can1,oscillator=12000000,interrupt=24,spimaxfrequency=2000000' | sudo tee -a /boot/firmware/config.txt
grep -qxF 'can' /etc/modules || echo 'can' | sudo tee -a /etc/modules



if ! dpkg -l | grep -q 'can-utils'; then
  echo "can-utils not found, installing..."
  sudo apt-get update
  sudo apt-get install -y can-utils
else
  echo "can-utils is already installed."
fi
