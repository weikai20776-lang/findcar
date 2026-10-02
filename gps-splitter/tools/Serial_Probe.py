import ctypes
from ctypes import wintypes
import os
import sys
import time
from datetime import datetime

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
OPEN_EXISTING = 3
FILE_FLAG_OVERLAPPED = 0x40000000
INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value

PURGE_TXABORT = 0x0001
PURGE_RXABORT = 0x0002
PURGE_TXCLEAR = 0x0004
PURGE_RXCLEAR = 0x0008
EV_RXCHAR = 0x0001

SETXOFF = 1
SETXON = 2
SETRTS = 3
CLRRTS = 4
SETDTR = 5
CLRDTR = 6
SETBREAK = 8
CLRBREAK = 9

ERROR_IO_PENDING = 997
WAIT_OBJECT_0 = 0
WAIT_TIMEOUT = 258

class DCB(ctypes.Structure):
    _fields_ = [
        ("DCBlength", wintypes.DWORD),
        ("BaudRate", wintypes.DWORD),
        ("Flags", wintypes.DWORD),
        ("wReserved", wintypes.WORD),
        ("XonLim", wintypes.WORD),
        ("XoffLim", wintypes.WORD),
        ("ByteSize", wintypes.BYTE),
        ("Parity", wintypes.BYTE),
        ("StopBits", wintypes.BYTE),
        ("XonChar", ctypes.c_char),
        ("XoffChar", ctypes.c_char),
        ("ErrorChar", ctypes.c_char),
        ("EofChar", ctypes.c_char),
        ("EvtChar", ctypes.c_char),
        ("wReserved1", wintypes.WORD),
    ]

class COMMTIMEOUTS(ctypes.Structure):
    _fields_ = [
        ("ReadIntervalTimeout", wintypes.DWORD),
        ("ReadTotalTimeoutMultiplier", wintypes.DWORD),
        ("ReadTotalTimeoutConstant", wintypes.DWORD),
        ("WriteTotalTimeoutMultiplier", wintypes.DWORD),
        ("WriteTotalTimeoutConstant", wintypes.DWORD),
    ]

class COMSTAT(ctypes.Structure):
    _fields_ = [
        ("Flags", wintypes.DWORD),
        ("cbInQue", wintypes.DWORD),
        ("cbOutQue", wintypes.DWORD),
    ]

class COMMPROP(ctypes.Structure):
    _fields_ = [
        ("wPacketLength", wintypes.WORD),
        ("wPacketVersion", wintypes.WORD),
        ("dwServiceMask", wintypes.DWORD),
        ("dwReserved1", wintypes.DWORD),
        ("dwMaxTxQueue", wintypes.DWORD),
        ("dwMaxRxQueue", wintypes.DWORD),
        ("dwMaxBaud", wintypes.DWORD),
        ("dwProvSubType", wintypes.DWORD),
        ("dwProvCapabilities", wintypes.DWORD),
        ("dwSettableParams", wintypes.DWORD),
        ("dwSettableBaud", wintypes.DWORD),
        ("wSettableData", wintypes.WORD),
        ("wSettableStopParity", wintypes.WORD),
        ("dwCurrentTxQueue", wintypes.DWORD),
        ("dwCurrentRxQueue", wintypes.DWORD),
        ("dwProvSpec1", wintypes.DWORD),
        ("dwProvSpec2", wintypes.DWORD),
        ("wcProvChar", wintypes.WCHAR),
    ]

ULONG_PTR = wintypes.WPARAM

class OVERLAPPED(ctypes.Structure):
    _fields_ = [
        ("Internal", ULONG_PTR),
        ("InternalHigh", ULONG_PTR),
        ("Offset", wintypes.DWORD),
        ("OffsetHigh", wintypes.DWORD),
        ("hEvent", wintypes.HANDLE),
    ]

kernel32.CreateFileW.argtypes = [
    wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID,
    wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE
]
kernel32.CreateFileW.restype = wintypes.HANDLE

kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.CloseHandle.restype = wintypes.BOOL
kernel32.SetupComm.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.DWORD]
kernel32.SetupComm.restype = wintypes.BOOL
kernel32.GetCommState.argtypes = [wintypes.HANDLE, ctypes.POINTER(DCB)]
kernel32.GetCommState.restype = wintypes.BOOL
kernel32.SetCommState.argtypes = [wintypes.HANDLE, ctypes.POINTER(DCB)]
kernel32.SetCommState.restype = wintypes.BOOL
kernel32.GetCommTimeouts.argtypes = [wintypes.HANDLE, ctypes.POINTER(COMMTIMEOUTS)]
kernel32.GetCommTimeouts.restype = wintypes.BOOL
kernel32.SetCommTimeouts.argtypes = [wintypes.HANDLE, ctypes.POINTER(COMMTIMEOUTS)]
kernel32.SetCommTimeouts.restype = wintypes.BOOL
kernel32.GetCommProperties.argtypes = [wintypes.HANDLE, ctypes.POINTER(COMMPROP)]
kernel32.GetCommProperties.restype = wintypes.BOOL
kernel32.ClearCommError.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD), ctypes.POINTER(COMSTAT)]
kernel32.ClearCommError.restype = wintypes.BOOL
kernel32.PurgeComm.argtypes = [wintypes.HANDLE, wintypes.DWORD]
kernel32.PurgeComm.restype = wintypes.BOOL
kernel32.SetCommMask.argtypes = [wintypes.HANDLE, wintypes.DWORD]
kernel32.SetCommMask.restype = wintypes.BOOL
kernel32.GetCommMask.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
kernel32.GetCommMask.restype = wintypes.BOOL
kernel32.GetCommModemStatus.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
kernel32.GetCommModemStatus.restype = wintypes.BOOL
kernel32.EscapeCommFunction.argtypes = [wintypes.HANDLE, wintypes.DWORD]
kernel32.EscapeCommFunction.restype = wintypes.BOOL
kernel32.WaitCommEvent.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD), ctypes.POINTER(OVERLAPPED)]
kernel32.WaitCommEvent.restype = wintypes.BOOL
kernel32.CreateEventW.argtypes = [wintypes.LPVOID, wintypes.BOOL, wintypes.BOOL, wintypes.LPCWSTR]
kernel32.CreateEventW.restype = wintypes.HANDLE
kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
kernel32.WaitForSingleObject.restype = wintypes.DWORD
kernel32.GetOverlappedResult.argtypes = [wintypes.HANDLE, ctypes.POINTER(OVERLAPPED), ctypes.POINTER(wintypes.DWORD), wintypes.BOOL]
kernel32.GetOverlappedResult.restype = wintypes.BOOL
kernel32.CancelIoEx.argtypes = [wintypes.HANDLE, ctypes.POINTER(OVERLAPPED)]
kernel32.CancelIoEx.restype = wintypes.BOOL

lines = []

def log(msg=""):
    print(msg, flush=True)
    lines.append(msg)

def last_error_text(err=None):
    if err is None:
        err = ctypes.get_last_error()
    try:
        return f"{err} ({ctypes.FormatError(err).strip()})"
    except Exception:
        return str(err)

def result(name, ok, detail=""):
    if ok:
        log(f"[OK]   {name}" + (f" | {detail}" if detail else ""))
    else:
        err = ctypes.get_last_error()
        log(f"[FAIL] {name} | Win32={last_error_text(err)}" + (f" | {detail}" if detail else ""))
    return bool(ok)

def cbyte(v):
    if isinstance(v, bytes):
        return v[0] if v else 0
    if isinstance(v, str):
        return ord(v[0]) if v else 0
    return int(v)

def dcb_text(d):
    return (
        f"Baud={d.BaudRate}, ByteSize={d.ByteSize}, Parity={d.Parity}, "
        f"StopBits={d.StopBits}, Flags=0x{d.Flags:08X}, "
        f"XonLim={d.XonLim}, XoffLim={d.XoffLim}, "
        f"Xon=0x{cbyte(d.XonChar):02X}, Xoff=0x{cbyte(d.XoffChar):02X}, "
        f"Evt=0x{cbyte(d.EvtChar):02X}"
    )

def timeout_text(t):
    return (
        f"RI={t.ReadIntervalTimeout}, RTM={t.ReadTotalTimeoutMultiplier}, "
        f"RTC={t.ReadTotalTimeoutConstant}, WTM={t.WriteTotalTimeoutMultiplier}, "
        f"WTC={t.WriteTotalTimeoutConstant}"
    )

def main():
    port = sys.argv[1].upper() if len(sys.argv) >= 2 else input("COM port (例如 COM11 或 COM6): ").strip().upper()
    if not port.startswith("COM"):
        port = "COM" + port
    path = r"\\.\\" + port

    log("GPS Serial API Probe V1")
    log(f"Time: {datetime.now().isoformat(timespec='seconds')}")
    log(f"Port: {port}")
    log("Mode: GENERIC_READ|GENERIC_WRITE, exclusive, FILE_FLAG_OVERLAPPED")
    log("")

    h = kernel32.CreateFileW(
        path,
        GENERIC_READ | GENERIC_WRITE,
        0,
        None,
        OPEN_EXISTING,
        FILE_FLAG_OVERLAPPED,
        None
    )
    if h == INVALID_HANDLE_VALUE or h is None:
        result("CreateFile", False, path)
        save(port)
        return 2

    result("CreateFile", True, path)
    try:
        result("SetupComm(4096,4096)", kernel32.SetupComm(h, 4096, 4096))

        prop = COMMPROP()
        ok = kernel32.GetCommProperties(h, ctypes.byref(prop))
        detail = ""
        if ok:
            detail = (
                f"Packet={prop.wPacketLength}/{prop.wPacketVersion}, "
                f"MaxTx={prop.dwMaxTxQueue}, MaxRx={prop.dwMaxRxQueue}, "
                f"MaxBaud=0x{prop.dwMaxBaud:08X}, ProvSubType={prop.dwProvSubType}, "
                f"Caps=0x{prop.dwProvCapabilities:08X}, "
                f"SettableParams=0x{prop.dwSettableParams:08X}, "
                f"SettableBaud=0x{prop.dwSettableBaud:08X}, "
                f"Data=0x{prop.wSettableData:04X}, StopParity=0x{prop.wSettableStopParity:04X}, "
                f"CurrentTx={prop.dwCurrentTxQueue}, CurrentRx={prop.dwCurrentRxQueue}"
            )
        result("GetCommProperties", ok, detail)

        dcb = DCB()
        dcb.DCBlength = ctypes.sizeof(DCB)
        ok = kernel32.GetCommState(h, ctypes.byref(dcb))
        result("GetCommState(before)", ok, dcb_text(dcb) if ok else "")
        if ok:
            dcb.BaudRate = 4800
            dcb.ByteSize = 8
            dcb.Parity = 0
            dcb.StopBits = 0
            dcb.Flags = 0x00000001  # fBinary only; no flow control, DTR/RTS disabled
            dcb.XonChar = b"\x11"
            dcb.XoffChar = b"\x13"
            result("SetCommState(4800,n,8,1)", kernel32.SetCommState(h, ctypes.byref(dcb)))

            verify = DCB()
            verify.DCBlength = ctypes.sizeof(DCB)
            ok2 = kernel32.GetCommState(h, ctypes.byref(verify))
            result("GetCommState(after)", ok2, dcb_text(verify) if ok2 else "")

        t0 = COMMTIMEOUTS()
        ok = kernel32.GetCommTimeouts(h, ctypes.byref(t0))
        result("GetCommTimeouts(before)", ok, timeout_text(t0) if ok else "")

        t = COMMTIMEOUTS(50, 0, 500, 0, 500)
        result("SetCommTimeouts", kernel32.SetCommTimeouts(h, ctypes.byref(t)), timeout_text(t))

        t1 = COMMTIMEOUTS()
        ok = kernel32.GetCommTimeouts(h, ctypes.byref(t1))
        result("GetCommTimeouts(after)", ok, timeout_text(t1) if ok else "")

        errors = wintypes.DWORD(0)
        stat = COMSTAT()
        ok = kernel32.ClearCommError(h, ctypes.byref(errors), ctypes.byref(stat))
        result("ClearCommError", ok, f"errors=0x{errors.value:08X}, in={stat.cbInQue}, out={stat.cbOutQue}" if ok else "")

        result("PurgeComm(all)", kernel32.PurgeComm(h, PURGE_TXABORT | PURGE_RXABORT | PURGE_TXCLEAR | PURGE_RXCLEAR))

        result("SetCommMask(EV_RXCHAR)", kernel32.SetCommMask(h, EV_RXCHAR))
        mask = wintypes.DWORD(0)
        ok = kernel32.GetCommMask(h, ctypes.byref(mask))
        result("GetCommMask", ok, f"mask=0x{mask.value:08X}" if ok else "")

        modem = wintypes.DWORD(0)
        ok = kernel32.GetCommModemStatus(h, ctypes.byref(modem))
        result("GetCommModemStatus", ok, f"status=0x{modem.value:08X}" if ok else "")

        for code, name in [
            (SETDTR, "EscapeCommFunction(SETDTR)"),
            (CLRDTR, "EscapeCommFunction(CLRDTR)"),
            (SETRTS, "EscapeCommFunction(SETRTS)"),
            (CLRRTS, "EscapeCommFunction(CLRRTS)"),
            (SETBREAK, "EscapeCommFunction(SETBREAK)"),
            (CLRBREAK, "EscapeCommFunction(CLRBREAK)"),
        ]:
            result(name, kernel32.EscapeCommFunction(h, code))

        evt = kernel32.CreateEventW(None, True, False, None)
        if not evt:
            result("CreateEvent(WaitCommEvent)", False)
        else:
            try:
                ov = OVERLAPPED()
                ov.hEvent = evt
                event_mask = wintypes.DWORD(0)
                ctypes.set_last_error(0)
                ok = kernel32.WaitCommEvent(h, ctypes.byref(event_mask), ctypes.byref(ov))
                if ok:
                    result("WaitCommEvent", True, f"event=0x{event_mask.value:08X} immediate")
                else:
                    err = ctypes.get_last_error()
                    if err == ERROR_IO_PENDING:
                        wr = kernel32.WaitForSingleObject(evt, 1500)
                        if wr == WAIT_OBJECT_0:
                            transferred = wintypes.DWORD(0)
                            ok2 = kernel32.GetOverlappedResult(h, ctypes.byref(ov), ctypes.byref(transferred), False)
                            result("WaitCommEvent", ok2, f"event=0x{event_mask.value:08X} overlapped")
                        elif wr == WAIT_TIMEOUT:
                            log("[INFO] WaitCommEvent | timeout after 1500 ms (not an API failure; no RX event arrived)")
                            kernel32.CancelIoEx(h, ctypes.byref(ov))
                        else:
                            log(f"[FAIL] WaitCommEvent wait | WaitForSingleObject={wr}")
                            kernel32.CancelIoEx(h, ctypes.byref(ov))
                    else:
                        log(f"[FAIL] WaitCommEvent | Win32={last_error_text(err)}")
            finally:
                kernel32.CloseHandle(evt)

        time.sleep(0.25)
        errors = wintypes.DWORD(0)
        stat = COMSTAT()
        ok = kernel32.ClearCommError(h, ctypes.byref(errors), ctypes.byref(stat))
        result("ClearCommError(final)", ok, f"errors=0x{errors.value:08X}, in={stat.cbInQue}, out={stat.cbOutQue}" if ok else "")

    finally:
        kernel32.CloseHandle(h)
        log("[OK]   CloseHandle")
        save(port)

    return 0

def save(port):
    try:
        base = os.path.dirname(os.path.abspath(sys.executable if getattr(sys, "frozen", False) else __file__))
        path = os.path.join(base, f"serial_probe_{port}.txt")
        with open(path, "w", encoding="utf-8-sig") as f:
            f.write("\n".join(lines) + "\n")
        print(f"\nLog saved: {path}")
    except Exception as e:
        print(f"\nCould not save log: {e}")

if __name__ == "__main__":
    try:
        rc = main()
    except Exception as e:
        log(f"[FATAL] {type(e).__name__}: {e}")
        try:
            save("UNKNOWN")
        except Exception:
            pass
        rc = 99
    input("\nPress Enter to close...")
    raise SystemExit(rc)
