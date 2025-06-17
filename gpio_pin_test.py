import gpiod
import time
import subprocess

GPIO_CHIP = "gpiochip0"
GPIO_LINE = 19

def enable_pull_up(pin):
    try:
        # Run pinctrl command to enable pull-up on the pin
        subprocess.run(["sudo", "pinctrl", "-e", "set", str(pin), "pu"], check=True)
        print(f"Pull-up resistor enabled on GPIO{pin}")
    except subprocess.CalledProcessError as e:
        print(f"Failed to enable pull-up resistor: {e}")


def main():
    enable_pull_up(GPIO_LINE)

    chip = gpiod.Chip(GPIO_CHIP)
    line = chip.get_line(GPIO_LINE)

    line.request(consumer="button-monitor", type=gpiod.LINE_REQ_DIR_IN)

    print(f"Monitoring button on GPIO{GPIO_LINE} ..")
    try:
        while True:
            value = line.get_value()
            if value == 0:  # Active LOW: button is pressed
                print("Button Is Pressed!")
                while line.get_value() == 0:
                    time.sleep(0.01)  # Wait for button release (debounce)
            time.sleep(0.01)
    except KeyboardInterrupt:
        print("\nExiting.")
    finally:
        line.release()

if __name__ == "__main__":
    main()