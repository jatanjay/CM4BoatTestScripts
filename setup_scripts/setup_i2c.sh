#!/bin/bash
# auth: jatan pandya / quiretech llc

sudo raspi-config nonint do_i2c 0
sudo modprobe i2c-dev
sudo modprobe i2c-bcm2708
grep -qxF 'i2c-dev' /etc/modules || echo 'i2c-dev' | sudo tee -a /etc/modules
grep -qxF 'i2c-bcm2708' /etc/modules || echo 'i2c-bcm2708' | sudo tee -a /etc/modules
grep -qxF 'dtparam=i2c_arm=on' /boot/firmware/config.txt || echo 'dtparam=i2c_arm=on' | sudo tee -a /boot/firmware/config.txt

