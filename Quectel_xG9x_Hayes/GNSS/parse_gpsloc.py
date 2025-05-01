import sys

def parse_gps_and_generate_maps_link(gps_string):
    """
    Parses a GPS data string, prints latitude and longitude, and generates a Google Maps link.

    Args:
        gps_string: The GPS data string to be parsed.
    """
    def parse_gps_data(gps_string):
        """
        Parses a GPS data string and returns latitude and longitude as text.

        Args:
            gps_string: The GPS data string.

        Returns:
            A tuple containing latitude and longitude as strings, or None if parsing fails.
        """
        try:
            parts = gps_string.split(',')
            latitude_str = parts[1]
            longitude_str = parts[2]

            # Parse latitude
            lat_degrees = int(latitude_str[:2])
            lat_minutes = float(latitude_str[2:-1])
            lat_direction = latitude_str[-1]

            latitude_decimal = lat_degrees + (lat_minutes / 60)
            if lat_direction == 'S':
                latitude_decimal *= -1

            # Parse longitude
            lon_degrees = int(longitude_str[:3])
            lon_minutes = float(longitude_str[3:-1])
            lon_direction = longitude_str[-1]

            longitude_decimal = lon_degrees + (lon_minutes / 60)
            if lon_direction == 'W':
                longitude_decimal *= -1

            return f"{latitude_decimal:.6f}", f"{longitude_decimal:.6f}"

        except (ValueError, IndexError):
            return None  # Indicate parsing failure

    result = parse_gps_data(gps_string)

    if result:
        latitude, longitude = result
        print(f"Latitude: {latitude}")
        print(f"Longitude: {longitude}")
        google_maps_link = f"https://www.google.com/maps/place/{latitude},{longitude}"
        print(f"Google Maps Link: {google_maps_link}")
    else:
        print("Error parsing GPS data.")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        gps_data = sys.argv[1]
        parse_gps_and_generate_maps_link(gps_data)
    else:
        print("Usage: python parse.py \"gps_data_string\"")