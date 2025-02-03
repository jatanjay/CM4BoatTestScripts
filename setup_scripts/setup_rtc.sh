#!/bin/bash
# auth: jatan pandya / quiretech llc

grep -qxF 'dtoverlay=i2c-rtc,pcf85063a,i2c_csi_dsi,addr=0x51' /boot/firmware/config.txt || echo 'dtoverlay=i2c-rtc,pcf85063a,i2c_csi_dsi,addr=0x51' | sudo tee -a /boot/firmware/config.txt