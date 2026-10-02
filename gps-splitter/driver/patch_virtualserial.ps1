$ErrorActionPreference = "Stop"

$root = Join-Path $PSScriptRoot "..\..\deps\windows-driver-samples\serial\VirtualSerial2"
$deviceH = Join-Path $root "device.h"
$deviceC = Join-Path $root "device.c"
$queueH  = Join-Path $root "queue.h"
$queueC  = Join-Path $root "queue.c"

Write-Host "Patching VirtualSerial2 sources for GPS injection control channel..."

# Increase symbolic-link and buffering headroom.
$txt = Get-Content $deviceH -Raw
$txt = $txt.Replace(
    "#define SYMBOLIC_LINK_NAME_LENGTH   32",
    "#define SYMBOLIC_LINK_NAME_LENGTH   64"
)
Set-Content $deviceH $txt -Encoding utf8

$txt = Get-Content $queueH -Raw
$txt = $txt.Replace(
    "#define DATA_BUFFER_SIZE 1024",
    "#define DATA_BUFFER_SIZE 65536"
)
Set-Content $queueH $txt -Encoding utf8

# Add custom injection IOCTL.
$txt = Get-Content $queueC -Raw
$includeNeedle = '#include "internal.h"'
$includeReplacement = @'
#include "internal.h"

//
// GPS Splitter private control IOCTL.
// FILE_ANY_ACCESS lets the feeder open the secondary symbolic link with
// DesiredAccess=0, avoiding share conflicts with the program that owns COMx.
//
#define IOCTL_GPSVCOM_INJECT CTL_CODE(FILE_DEVICE_SERIAL_PORT, 0x800, METHOD_BUFFERED, FILE_ANY_ACCESS)

typedef struct _GPS_SERIAL_STATUS {
    ULONG   Errors;
    ULONG   HoldReasons;
    ULONG   AmountInInQueue;
    ULONG   AmountInOutQueue;
    BOOLEAN EofReceived;
    BOOLEAN WaitForImmediate;
} GPS_SERIAL_STATUS, *PGPS_SERIAL_STATUS;

typedef struct _GPS_SERIAL_CHARS {
    UCHAR EofChar;
    UCHAR ErrorChar;
    UCHAR BreakChar;
    UCHAR EventChar;
    UCHAR XonChar;
    UCHAR XoffChar;
} GPS_SERIAL_CHARS, *PGPS_SERIAL_CHARS;

typedef struct _GPS_SERIAL_HANDFLOW {
    ULONG ControlHandShake;
    ULONG FlowReplace;
    LONG  XonLimit;
    LONG  XoffLimit;
} GPS_SERIAL_HANDFLOW, *PGPS_SERIAL_HANDFLOW;

typedef struct _GPS_SERIAL_COMMPROP {
    USHORT PacketLength;
    USHORT PacketVersion;
    ULONG  ServiceMask;
    ULONG  Reserved1;
    ULONG  MaxTxQueue;
    ULONG  MaxRxQueue;
    ULONG  MaxBaud;
    ULONG  ProvSubType;
    ULONG  ProvCapabilities;
    ULONG  SettableParams;
    ULONG  SettableBaud;
    USHORT SettableData;
    USHORT SettableStopParity;
    ULONG  CurrentTxQueue;
    ULONG  CurrentRxQueue;
    ULONG  ProvSpec1;
    ULONG  ProvSpec2;
    WCHAR  ProvChar[1];
} GPS_SERIAL_COMMPROP, *PGPS_SERIAL_COMMPROP;
'@
if (-not $txt.Contains($includeNeedle)) {
    throw "queue.c include patch anchor not found"
}
$txt = $txt.Replace($includeNeedle, $includeReplacement)

$caseNeedle = @'
    case IOCTL_SERIAL_SET_BAUD_RATE:
'@

$caseReplacement = @'
    case IOCTL_SERIAL_GET_CHARS:
    {
        GPS_SERIAL_CHARS chars = {0};
        chars.XonChar = 0x11;
        chars.XoffChar = 0x13;
        status = RequestCopyFromBuffer(
                    Request,
                    &chars,
                    sizeof(chars));
        break;
    }

    case IOCTL_SERIAL_SET_CHARS:
    {
        GPS_SERIAL_CHARS chars = {0};
        status = RequestCopyToBuffer(
                    Request,
                    &chars,
                    sizeof(chars));
        break;
    }

    case IOCTL_SERIAL_GET_HANDFLOW:
    {
        GPS_SERIAL_HANDFLOW handflow = {0};
        status = RequestCopyFromBuffer(
                    Request,
                    &handflow,
                    sizeof(handflow));
        break;
    }

    case IOCTL_SERIAL_SET_HANDFLOW:
    {
        GPS_SERIAL_HANDFLOW handflow = {0};
        status = RequestCopyToBuffer(
                    Request,
                    &handflow,
                    sizeof(handflow));
        break;
    }

    case IOCTL_SERIAL_GET_PROPERTIES:
    {
        GPS_SERIAL_COMMPROP properties = {0};

        properties.PacketLength = (USHORT)sizeof(properties);
        properties.PacketVersion = 2;
        properties.ServiceMask = 1;
        properties.MaxTxQueue = 0;
        properties.MaxRxQueue = 65536;
        properties.MaxBaud = 115200;
        properties.ProvSubType = 1;
        properties.CurrentTxQueue = 0;
        properties.CurrentRxQueue = 65536;

        status = RequestCopyFromBuffer(
                    Request,
                    &properties,
                    sizeof(properties));
        break;
    }

    case IOCTL_SERIAL_GET_COMMSTATUS:
    {
        GPS_SERIAL_STATUS commStatus = {0};
        size_t availableData = 0;

        RingBufferGetAvailableData(
                    &queueContext->RingBuffer,
                    &availableData);

        commStatus.Errors = 0;
        commStatus.HoldReasons = 0;
        commStatus.AmountInInQueue =
            (availableData > MAXULONG) ? MAXULONG : (ULONG)availableData;
        commStatus.AmountInOutQueue = 0;
        commStatus.EofReceived = FALSE;
        commStatus.WaitForImmediate = FALSE;

        status = RequestCopyFromBuffer(
                    Request,
                    &commStatus,
                    sizeof(commStatus));
        break;
    }

    case IOCTL_SERIAL_PURGE:
    {
        ULONG purgeMask = 0;

        status = RequestCopyToBuffer(
                    Request,
                    &purgeMask,
                    sizeof(purgeMask));

        if (NT_SUCCESS(status)) {
            RingBufferInitialize(
                    &queueContext->RingBuffer,
                    queueContext->Buffer,
                    sizeof(queueContext->Buffer));
        }

        break;
    }

    case IOCTL_SERIAL_GET_MODEMSTATUS:
    case IOCTL_SERIAL_GET_DTRRTS:
    case IOCTL_SERIAL_GET_WAIT_MASK:
    {
        ULONG value = 0;
        status = RequestCopyFromBuffer(
                    Request,
                    &value,
                    sizeof(value));
        break;
    }

    case IOCTL_GPSVCOM_INJECT:
    {
        WDFMEMORY memory;
        size_t bufferLength = 0;
        WDFREQUEST savedRequest;

        status = WdfRequestRetrieveInputMemory(Request, &memory);
        if (NT_SUCCESS(status)) {
            PUCHAR inputBuffer =
                (PUCHAR)WdfMemoryGetBuffer(memory, &bufferLength);

            if (InputBufferLength > bufferLength) {
                status = STATUS_BUFFER_TOO_SMALL;
            }
            else if (InputBufferLength > 0) {
                status = RingBufferWrite(
                                &queueContext->RingBuffer,
                                inputBuffer,
                                InputBufferLength);
            }
        }

        //
        // Any reads that were waiting for data can now be dispatched back to
        // the default queue, where EvtIoRead will consume the injected bytes.
        //
        if (NT_SUCCESS(status)) {
            for (;;) {
                status = WdfIoQueueRetrieveNextRequest(
                                    queueContext->ReadQueue,
                                    &savedRequest);

                if (!NT_SUCCESS(status)) {
                    status = STATUS_SUCCESS;
                    break;
                }

                status = WdfRequestForwardToIoQueue(
                                    savedRequest,
                                    Queue);

                if (!NT_SUCCESS(status)) {
                    WdfRequestComplete(savedRequest, status);
                    break;
                }
            }
        }

        break;
    }

    case IOCTL_SERIAL_SET_BAUD_RATE:
'@

if (-not $txt.Contains($caseNeedle)) {
    throw "queue.c IOCTL patch anchor not found"
}
$txt = $txt.Replace($caseNeedle, $caseReplacement)

# The original Microsoft sample groups these four query/set IOCTLs into a
# no-op success block. V4 provides real handlers above, so remove the old
# duplicate case labels while leaving the remaining no-op cases intact.
$txt = $txt.Replace("    case IOCTL_SERIAL_SET_CHARS:`r`n", "")
$txt = $txt.Replace("    case IOCTL_SERIAL_GET_CHARS:`r`n", "")
$txt = $txt.Replace("    case IOCTL_SERIAL_GET_HANDFLOW:`r`n", "")
$txt = $txt.Replace("    case IOCTL_SERIAL_SET_HANDFLOW:`r`n", "")
$txt = $txt.Replace("    case IOCTL_SERIAL_SET_CHARS:`n", "")
$txt = $txt.Replace("    case IOCTL_SERIAL_GET_CHARS:`n", "")
$txt = $txt.Replace("    case IOCTL_SERIAL_GET_HANDFLOW:`n", "")
$txt = $txt.Replace("    case IOCTL_SERIAL_SET_HANDFLOW:`n", "")

# Re-insert the four V4 case labels if the cleanup above also matched the
# newly-added handlers. We anchor on each unique handler body.
$txt = $txt.Replace("    {`n        GPS_SERIAL_CHARS chars = {0};`n        chars.XonChar", "    case IOCTL_SERIAL_GET_CHARS:`n    {`n        GPS_SERIAL_CHARS chars = {0};`n        chars.XonChar")
$txt = $txt.Replace("    {`n        GPS_SERIAL_CHARS chars = {0};`n        status = RequestCopyToBuffer", "    case IOCTL_SERIAL_SET_CHARS:`n    {`n        GPS_SERIAL_CHARS chars = {0};`n        status = RequestCopyToBuffer")
$txt = $txt.Replace("    {`n        GPS_SERIAL_HANDFLOW handflow = {0};`n        status = RequestCopyFromBuffer", "    case IOCTL_SERIAL_GET_HANDFLOW:`n    {`n        GPS_SERIAL_HANDFLOW handflow = {0};`n        status = RequestCopyFromBuffer")
$txt = $txt.Replace("    {`n        GPS_SERIAL_HANDFLOW handflow = {0};`n        status = RequestCopyToBuffer", "    case IOCTL_SERIAL_SET_HANDFLOW:`n    {`n        GPS_SERIAL_HANDFLOW handflow = {0};`n        status = RequestCopyToBuffer")

Set-Content $queueC $txt -Encoding utf8

Write-Host "GPS injection patch applied successfully."
