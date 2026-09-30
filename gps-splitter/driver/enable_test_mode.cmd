@echo off
setlocal
echo ============================================================
echo Enable Windows TESTSIGNING mode for GPS Virtual COM testing
echo ============================================================
echo.
echo This changes Windows boot configuration and requires a reboot.
echo It is intended only for development/testing of this driver.
echo.

net session >nul 2>&1
if errorlevel 1 (
  echo ERROR: Please right-click this file and choose "Run as administrator".
  pause
  exit /b 1
)

bcdedit /set testsigning on
if errorlevel 1 (
  echo.
  echo Could not enable TESTSIGNING.
  echo If Windows reports that the value is protected by Secure Boot policy,
  echo disable Secure Boot in UEFI/BIOS, boot Windows, then run this file again.
  pause
  exit /b 2
)

echo.
echo TESTSIGNING has been enabled.
echo Restart Windows before installing the GPS Virtual COM test driver.
pause
