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
$queueStateReplacement = '$1' +
    [Environment]::NewLine + [Environment]::NewLine + '    ULONG           WaitMask;           // Current SetCommMask value' +
    [Environment]::NewLine + '    UCHAR           EofChar;' +
    [Environment]::NewLine + '    UCHAR           ErrorChar;' +
    [Environment]::NewLine + '    UCHAR           BreakChar;' +
    [Environment]::NewLine + '    UCHAR           EventChar;' +
    [Environment]::NewLine + '    UCHAR           XonChar;' +
    [Environment]::NewLine + '    UCHAR           XoffChar;' +
    [Environment]::NewLine + '    ULONG           ControlHandShake;' +
    [Environment]::NewLine + '    ULONG           FlowReplace;' +
    [Environment]::NewLine + '    LONG            XonLimit;' +
    [Environment]::NewLine + '    LONG            XoffLimit;' +
    [Environment]::NewLine + '    ULONG           DtrRtsState;' +
    [Environment]::NewLine + '    ULONG           TxQueueSize;' +
    [Environment]::NewLine + '    ULONG           RxQueueSize;'

$txt = [regex]::Replace(
    $txt,
    '(?m)^(\s*WDFQUEUE\s+WaitMaskQueue;\s*// Manual queue for pending ioctl wait-on-mask)\r?$',
    $queueStateReplacement,
    1
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
#define GPS_EV_RXCHAR 0x0001

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
    case IOCTL_SERIAL_SET_QUEUE_SIZE:
    {
        struct { ULONG InSize; ULONG OutSize; } queueSize = {0};
        status = RequestCopyToBuffer(Request, &queueSize, sizeof(queueSize));
        if (NT_SUCCESS(status)) {
            queueContext->RxQueueSize = (queueSize.InSize > 65536) ? 65536 : queueSize.InSize;
            queueContext->TxQueueSize = queueSize.OutSize;
        }
        break;
    }

    case IOCTL_SERIAL_SET_DTR:
        queueContext->DtrRtsState |= 0x00000001;
        status = STATUS_SUCCESS;
        break;

    case IOCTL_SERIAL_CLR_DTR:
        queueContext->DtrRtsState &= ~0x00000001;
        status = STATUS_SUCCESS;
        break;

    case IOCTL_SERIAL_SET_RTS:
        queueContext->DtrRtsState |= 0x00000002;
        status = STATUS_SUCCESS;
        break;

    case IOCTL_SERIAL_CLR_RTS:
        queueContext->DtrRtsState &= ~0x00000002;
        status = STATUS_SUCCESS;
        break;

    case IOCTL_SERIAL_SET_BREAK_ON:
    case IOCTL_SERIAL_SET_BREAK_OFF:
    case IOCTL_SERIAL_IMMEDIATE_CHAR:
        status = STATUS_SUCCESS;
        break;
    case IOCTL_SERIAL_GET_CHARS:
    {
        GPS_SERIAL_CHARS chars = {0};
        chars.EofChar = queueContext->EofChar;
        chars.ErrorChar = queueContext->ErrorChar;
        chars.BreakChar = queueContext->BreakChar;
        chars.EventChar = queueContext->EventChar;
        chars.XonChar = queueContext->XonChar;
        chars.XoffChar = queueContext->XoffChar;
        status = RequestCopyFromBuffer(Request, &chars, sizeof(chars));
        break;
    }

    case IOCTL_SERIAL_SET_CHARS:
    {
        GPS_SERIAL_CHARS chars = {0};
        status = RequestCopyToBuffer(Request, &chars, sizeof(chars));
        if (NT_SUCCESS(status)) {
            queueContext->EofChar = chars.EofChar;
            queueContext->ErrorChar = chars.ErrorChar;
            queueContext->BreakChar = chars.BreakChar;
            queueContext->EventChar = chars.EventChar;
            queueContext->XonChar = chars.XonChar;
            queueContext->XoffChar = chars.XoffChar;
        }
        break;
    }

    case IOCTL_SERIAL_GET_HANDFLOW:
    {
        GPS_SERIAL_HANDFLOW handflow = {0};
        handflow.ControlHandShake = queueContext->ControlHandShake;
        handflow.FlowReplace = queueContext->FlowReplace;
        handflow.XonLimit = queueContext->XonLimit;
        handflow.XoffLimit = queueContext->XoffLimit;
        status = RequestCopyFromBuffer(Request, &handflow, sizeof(handflow));
        break;
    }

    case IOCTL_SERIAL_SET_HANDFLOW:
    {
        GPS_SERIAL_HANDFLOW handflow = {0};
        status = RequestCopyToBuffer(Request, &handflow, sizeof(handflow));
        if (NT_SUCCESS(status)) {
            queueContext->ControlHandShake = handflow.ControlHandShake;
            queueContext->FlowReplace = handflow.FlowReplace;
            queueContext->XonLimit = handflow.XonLimit;
            queueContext->XoffLimit = handflow.XoffLimit;
        }
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
        properties.MaxBaud = 0x00020000;
        properties.SettableBaud =
            0x00000200 | 0x00000800 | 0x00002000 |
            0x00004000 | 0x00020000 | 0x00040000;
        properties.ProvSubType = 1;
        properties.ProvCapabilities = 0x000000FF;
        properties.SettableParams = 0x0000007F;
        properties.SettableData = 0x000F;
        properties.SettableStopParity = 0x1F07;
        properties.CurrentTxQueue = queueContext->TxQueueSize;
        properties.CurrentRxQueue = queueContext->RxQueueSize;

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

        if (NT_SUCCESS(status) && (purgeMask & 0x00000008)) {
            RingBufferInitialize(
                    &queueContext->RingBuffer,
                    queueContext->Buffer,
                    sizeof(queueContext->Buffer));
        }

        break;
    }

    case IOCTL_SERIAL_GET_MODEMSTATUS:
    {
        ULONG value = 0x000000B0; // CTS | DSR | DCD asserted
        status = RequestCopyFromBuffer(Request, &value, sizeof(value));
        break;
    }

    case IOCTL_SERIAL_GET_DTRRTS:
    {
        ULONG value = queueContext->DtrRtsState;
        status = RequestCopyFromBuffer(Request, &value, sizeof(value));
        break;
    }

    case IOCTL_SERIAL_GET_WAIT_MASK:
    {
        ULONG value = queueContext->WaitMask;
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
        // MSComm32.OCX uses SetCommMask(EV_RXCHAR) + WaitCommEvent.
        //
        if (NT_SUCCESS(status) &&
            InputBufferLength > 0 &&
            (queueContext->WaitMask & GPS_EV_RXCHAR)) {

            WDFREQUEST waitRequest;
            NTSTATUS waitStatus = WdfIoQueueRetrieveNextRequest(
                                    queueContext->WaitMaskQueue,
                                    &waitRequest);

            if (NT_SUCCESS(waitStatus)) {
                ULONG eventMask = GPS_EV_RXCHAR;
                NTSTATUS copyStatus = RequestCopyFromBuffer(
                                        waitRequest,
                                        &eventMask,
                                        sizeof(eventMask));
                WdfRequestComplete(waitRequest, copyStatus);
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
# Initialize WaitCommEvent state.
$initialStateReplacement = '$0' +
    [Environment]::NewLine + '    queueContext->WaitMask = 0;' +
    [Environment]::NewLine + '    queueContext->EofChar = 0;' +
    [Environment]::NewLine + '    queueContext->ErrorChar = 0;' +
    [Environment]::NewLine + '    queueContext->BreakChar = 0;' +
    [Environment]::NewLine + '    queueContext->EventChar = 0;' +
    [Environment]::NewLine + '    queueContext->XonChar = 0x11;' +
    [Environment]::NewLine + '    queueContext->XoffChar = 0x13;' +
    [Environment]::NewLine + '    queueContext->ControlHandShake = 0;' +
    [Environment]::NewLine + '    queueContext->FlowReplace = 0;' +
    [Environment]::NewLine + '    queueContext->XonLimit = 0;' +
    [Environment]::NewLine + '    queueContext->XoffLimit = 0;' +
    [Environment]::NewLine + '    queueContext->DtrRtsState = 0;' +
    [Environment]::NewLine + '    queueContext->TxQueueSize = 0;' +
    [Environment]::NewLine + '    queueContext->RxQueueSize = 65536;'

$txt = [regex]::Replace(
    $txt,
    'RingBufferInitialize\(&queueContext->RingBuffer,\s*queueContext->Buffer,\s*sizeof\(queueContext->Buffer\)\);',
    $initialStateReplacement,
    1
)
# Replace the sample WaitCommEvent/SetCommMask block in place.
$oldWaitStart = $txt.IndexOf("    case IOCTL_SERIAL_WAIT_ON_MASK:")
$oldWaitEnd = $txt.IndexOf("    case IOCTL_SERIAL_SET_QUEUE_SIZE:")
if (($oldWaitStart -lt 0) -or ($oldWaitEnd -lt 0) -or ($oldWaitEnd -le $oldWaitStart)) {
    throw "Original wait-mask switch block not found"
}

$newWaitBlock = @'
    case IOCTL_SERIAL_WAIT_ON_MASK:
    {
        size_t availableData = 0;
        ULONG eventMask = 0;

        RingBufferGetAvailableData(
                            &queueContext->RingBuffer,
                            &availableData);

        if ((availableData > 0) &&
            (queueContext->WaitMask & GPS_EV_RXCHAR)) {
            eventMask = GPS_EV_RXCHAR;
            status = RequestCopyFromBuffer(
                            Request,
                            &eventMask,
                            sizeof(eventMask));
            break;
        }

        status = WdfRequestForwardToIoQueue(
                            Request,
                            queueContext->WaitMaskQueue);

        if (!NT_SUCCESS(status)) {
            WdfRequestComplete(Request, status);
        }
        return;
    }

    case IOCTL_SERIAL_SET_WAIT_MASK:
    {
        ULONG waitMask = 0;
        WDFREQUEST savedRequest;

        status = RequestCopyToBuffer(
                            Request,
                            &waitMask,
                            sizeof(waitMask));

        if (NT_SUCCESS(status)) {
            queueContext->WaitMask = waitMask;

            status = WdfIoQueueRetrieveNextRequest(
                            queueContext->WaitMaskQueue,
                            &savedRequest);

            if (NT_SUCCESS(status)) {
                ULONG eventMask = 0;
                NTSTATUS copyStatus = RequestCopyFromBuffer(
                                        savedRequest,
                                        &eventMask,
                                        sizeof(eventMask));
                WdfRequestComplete(savedRequest, copyStatus);
            }
            status = STATUS_SUCCESS;
        }
        break;
    }

'@

$txt = $txt.Substring(0, $oldWaitStart) + $newWaitBlock + $txt.Substring($oldWaitEnd)

# Remove the four no-op cases from the unmodified Microsoft sample BEFORE
# inserting the V4 handlers, so there are no duplicate switch case values.
$txt = [regex]::Replace(
    $txt,
    '(?m)^\s*case IOCTL_SERIAL_(SET_QUEUE_SIZE|SET_DTR|CLR_DTR|SET_RTS|CLR_RTS|SET_BREAK_ON|SET_BREAK_OFF|IMMEDIATE_CHAR|SET_CHARS|GET_CHARS|GET_HANDFLOW|SET_HANDFLOW):\r?\n',
    ''
)

# Make GetCommTimeouts round-trip the values previously supplied by SetCommTimeouts.
$txt = $txt.Replace(
    '        SERIAL_TIMEOUTS timeoutValues = {0};' + [Environment]::NewLine + [Environment]::NewLine + '        status = RequestCopyFromBuffer(Request,',
    '        SERIAL_TIMEOUTS timeoutValues = {0};' + [Environment]::NewLine + [Environment]::NewLine + '        GetTimeouts(deviceContext, &timeoutValues);' + [Environment]::NewLine + [Environment]::NewLine + '        status = RequestCopyFromBuffer(Request,'
)

$txt = $txt.Replace($caseNeedle, $caseReplacement)

Set-Content $queueC $txt -Encoding utf8

Write-Host "GPS injection patch applied successfully."
