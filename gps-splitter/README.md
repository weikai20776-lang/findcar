# GPS Splitter Driver Prototype

This branch is the Windows 10/11 prototype for the GPS multi-program splitter.

## Goal

- Read one physical NMEA GPS COM port.
- Automatically detect baud rate.
- Display latitude, longitude, satellite count and speed.
- Feed the same NMEA byte stream to up to five virtual COM ports.
- Default output ports: COM5-COM9.

## Build artifact

GitHub Actions builds a ZIP containing:

- `GPS_Splitter.exe`
- UMDF 2 virtual serial driver package
- `devcon.exe`
- test install/uninstall scripts

## Important

The driver is currently a **test/development build**, not a production Microsoft-signed driver.
A clean production Windows 10/11 system can only use the final package without Test Mode after the driver package has been submitted through Microsoft's production driver-signing process.

The virtual serial driver is based on Microsoft's Windows Driver Samples VirtualSerial2 UMDF 2 sample and is being used here as a development foundation.
