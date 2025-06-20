"""
6/18 - minor fix (init press_time to None before the loop) : jpandya
6/20 - timeout seconds increased to 20
"""

import gpiod
import time
import subprocess
from datetime import datetime



# NMEA device user button is wired to GPIO19
CHIP_NAME = "gpiochip0"
LINE_OFFSET = 19  # GPIO pin number, GPIO19


time_out_sec = 20

# Enable pull-up on the pin
def enable_pull_up(pin):
    try:
        # Run pinctrl command to enable pull-up on the pin
        subprocess.run(["sudo", "pinctrl", "-e", "set", str(pin), "pu"], check=True)
        print(f"Pull-up resistor enabled on GPIO{pin}")
    except subprocess.CalledProcessError as e:
        print(f"Failed to enable pull-up resistor: {e}")

# Timestamp formatting helper function
def get_timestamp():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")

# Determine the button press duration time and call reset/provisioning programs
def button_press_duration(press_time):
    release_time = datetime.now()
    duration = (release_time - press_time).total_seconds()
    print(f"Button was pressed for {duration:.3f} seconds")

    if duration > 10:
        # Reset the device to factory defaults
        print("Long press (> 10 seconds)")
        subprocess.run(["sudo", "/home/viam/viam-factory-reset.sh"], check=True)
    elif 3 <= duration <= 10:
        # Put the device into Provisioning Mode
        print("Medium press (3-10 seconds)")
    else:
        # Ignore short button presses
        print("Short press (< 3 seconds)")

# Main monitoring function
def main():
    enable_pull_up(LINE_OFFSET)
    chip = gpiod.Chip(CHIP_NAME)
    line = chip.get_line(LINE_OFFSET)

    # Request the line for both edge events
    line.request(consumer="button-monitor", type=gpiod.LINE_REQ_EV_BOTH_EDGES)

    print(f"Monitoring GPIO{LINE_OFFSET} on {CHIP_NAME} for button press...")

    press_time = None  # Initialize before the loop

    try:
        while True:
            if line.event_wait(sec=time_out_sec):
                evt = line.event_read()
                evt_time = datetime.now()

                if evt.type == gpiod.LineEvent.FALLING_EDGE:
                    press_time = evt_time
                    print(f"[{get_timestamp()}] Falling edge (button pressed)")
                    subprocess.run(["sudo", "pinctrl", "20,21", "op", "dh"], check=True)

                elif evt.type == gpiod.LineEvent.RISING_EDGE:
                    print(f"[{get_timestamp()}] Rising edge (button released)")
                    subprocess.run(["sudo", "pinctrl", "16,20,21", "op", "dl"], check=True)
                    if press_time is not None:
                        button_press_duration(press_time)
                        press_time = None
                    else:
                        print("Warning: RISING edge detected without a prior FALLING edge.")
            else:
                print("No event detected within timeout.")

    except KeyboardInterrupt:
        print("\nExiting...")

    finally:
        line.release()
        chip.close()

if __name__ == "__main__":
    main()