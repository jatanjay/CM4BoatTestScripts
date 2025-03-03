


echo "RESET HIGH LO"


sudo pinctrl 6 op dh
sleep 3
sudo pinctrl 6 op dl


echo "RESET PWR BTN"

sudo pinctrl 18 op dl
sleep 2
sudo pinctrl 18 op dh
