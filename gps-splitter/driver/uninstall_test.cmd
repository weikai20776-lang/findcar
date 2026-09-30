@echo off
setlocal
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
  echo Please run as administrator.
  pause
  exit /b 1
)
for %%P in (5 6 7 8 9) do (
  devcon.exe remove "ROOT\GPSVCOM%%P"
)
echo Removed GPS virtual COM test devices.
pause
