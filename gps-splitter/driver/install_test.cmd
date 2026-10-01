@echo off
setlocal
cd /d "%~dp0"

echo ============================================================
echo GPS Virtual COM TEST DRIVER installer
echo ============================================================
echo.
echo This is a TEST-SIGNED driver for validation only.
echo Windows must be in TESTSIGNING mode. Secure Boot normally must
echo be disabled before TESTSIGNING can be enabled.
echo.

net session >nul 2>&1
if errorlevel 1 (
  echo ERROR: Please right-click this file and choose "Run as administrator".
  pause
  exit /b 1
)

if not exist "GPSVCOM-Test.cer" (
  echo ERROR: GPSVCOM-Test.cer not found.
  pause
  exit /b 1
)

if not exist "WDKTestCert.cer" (
  echo ERROR: WDKTestCert.cer not found.
  pause
  exit /b 1
)

if not exist "devcon.exe" (
  echo ERROR: devcon.exe not found.
  pause
  exit /b 1
)

if not exist "virtualserial2um.inf" (
  echo ERROR: virtualserial2um.inf not found.
  pause
  exit /b 1
)

bcdedit /enum {current} | findstr /i "testsigning" | findstr /i "Yes" >nul
if errorlevel 1 (
  echo.
  echo TESTSIGNING is not enabled.
  echo Run enable_test_mode.cmd as Administrator, reboot, then run this installer again.
  echo If BCDEdit says the value is protected by Secure Boot policy,
  echo disable Secure Boot in UEFI/BIOS first.
  echo.
  pause
  exit /b 2
)

echo Installing GPS catalog test certificate...
certutil -f -addstore Root "GPSVCOM-Test.cer"
if errorlevel 1 goto :cert_error
certutil -f -addstore TrustedPublisher "GPSVCOM-Test.cer"
if errorlevel 1 goto :cert_error

echo Installing WDK driver binary test certificate...
certutil -f -addstore Root "WDKTestCert.cer"
if errorlevel 1 goto :cert_error
certutil -f -addstore TrustedPublisher "WDKTestCert.cer"
if errorlevel 1 goto :cert_error

for %%P in (5 6 7 8 9) do (
  echo.
  echo Installing GPS Virtual COM%%P ...
  devcon.exe install virtualserial2um.inf ROOT\GPSVCOM%%P
  if errorlevel 1 (
    echo WARNING: COM%%P installation returned an error.
  )
)

echo.
echo ============================================================
echo Installation command completed.
echo Open Device Manager ^> Ports ^(COM ^& LPT^) and check COM5-COM9.
echo ============================================================
pause
exit /b 0

:cert_error
echo ERROR: Could not install the test certificate.
pause
exit /b 3
