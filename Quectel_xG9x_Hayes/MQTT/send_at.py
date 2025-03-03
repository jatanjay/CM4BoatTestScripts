import serial
import time

# Open the serial port /dev/ttyAMA0
ser = serial.Serial('/dev/ttyS0', 115200, timeout=1)  # Adjust baudrate as needed

# Function to send AT command and read the response
def send_at_command(command):
    # Write the AT command
    ser.write((command + '\r\n').encode())
    
    # Wait a moment for the device to respond
    time.sleep(1)
    
    # Read the response from the serial port
    response = ser.read_all().decode('utf-8')
    
    # Print the response
    print(f"Response to '{command}':\n{response}")
    
# Example of sending an AT command
send_at_command('AT')  # Standard AT command to check if the device is responsive
send_at_command('AT+COPS?')
send_at_command('AT+CREG=2')
send_at_command('AT+QGPSCFG="autogps",1')
send_at_command('AT+QGPS?')
send_at_command('AT+QGPS=1')
send_at_command('AT+QGPSLOC=0')




# Close the serial port
ser.close()
