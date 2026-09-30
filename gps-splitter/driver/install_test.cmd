@echo off
setlocal
cd /d "%~dp0"
echo ============================================================
echo GPS Virtual COM TEST DRIVER installer
echo ============================================================
echo.
echo This is a TEST build. Windows may require Test Mode / disabled
echo signature enforcement because this package is not Microsoft-signed.
echo.
net session >nul 2>&1
if errorlevel 1 (
  echo Please right-click this file and choose "Run as administrator".
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
for %%P in (5 6 7 8 9) do (
  echo.
  echo Installing COM%%P ...
  devcon.exe install virtualserial2um.inf ROOT\GPSVCOM%%P
)
echo.
echo Finished. Open Device Manager and check Ports (COM and LPT).
pause
