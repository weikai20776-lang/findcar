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
'@
if (-not $txt.Contains($includeNeedle)) {
    throw "queue.c include patch anchor not found"
}
$txt = $txt.Replace($includeNeedle, $includeReplacement)

$caseNeedle = @'
    case IOCTL_SERIAL_SET_BAUD_RATE:
'@

$caseReplacement = @'
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
Set-Content $queueC $txt -Encoding utf8

Write-Host "GPS injection patch applied successfully."
