# GPS Splitter Windows Prototype

This package is the first installable Windows 10/11 validation build of the GPS splitter.

## What is included

- \`app/GPS_Splitter.exe\`
- \`driver/VirtualSerial2um.dll\`
- \`driver/virtualserial2um.inf\`
- \`driver/WUDF.cat\`
- \`driver/GPSVCOM-Test.cer\`
- \`driver/devcon.exe\`
- test install/uninstall scripts

## Architecture

The virtual serial driver creates COM5-COM9. Each virtual port also exposes a private
control path such as:

\`\\\\.\\GPSVCOMCTL_COM5\`

GPS_Splitter opens that private path with zero read/write access and injects NMEA bytes
using a private FILE_ANY_ACCESS IOCTL. A third-party program can therefore open COM5
normally and read the injected GPS data.

There are no hidden COM15/COM16 ports in this design.

## Test installation

This package is test-signed, not production-signed.

1. Close FabulaTech/com0com and any previous virtual-COM software using COM5-COM9.
2. Run \`driver/enable_test_mode.cmd\` as Administrator.
3. If BCDEdit says the setting is blocked by Secure Boot, disable Secure Boot in UEFI/BIOS.
4. Reboot Windows.
5. Run \`driver/install_test.cmd\` as Administrator.
6. Open Device Manager and confirm GPS Virtual Serial Port COM5-COM9 exist.
7. Run \`app/GPS_Splitter.exe\`.
8. Select your physical GPS source COM (for the current test device: COM11).
9. Auto-detect baud, then enable COM5 and COM6 and start splitting.
10. Third-party program A: COM5 / 4800. Program B: COM6 / 4800.

## Remove test driver

Run \`driver/uninstall_test.cmd\` as Administrator.

After testing, run \`driver/disable_test_mode.cmd\` as Administrator and reboot if you
want to return Windows to normal signing mode.

## Production portability

This development package is intentionally test-signed. For a final build that installs
on a clean Windows 10/11 PC with Secure Boot enabled and without TESTSIGNING, the driver
catalog must be submitted through Microsoft's production driver-signing process.
