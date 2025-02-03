#!/bin/bash
# auth: jatan pandya / quiretech llc

echo "D1 LED Test w/ GPIO"

echo "RED"
sudo pinctrl 20,21 op dh
sleep 1
sudo pinctrl 16,20,21 op dl

echo "GREEN"
sudo pinctrl 16,21 op dh
sleep 1
sudo pinctrl 16,20,21 op dl

echo "BLUE"
sudo pinctrl 16,20 op dh
sleep 1
sudo pinctrl 16,20,21 op dl

echo "WHITE"
sudo pinctrl 16,20,21 op dl
