@echo off
setlocal
echo Disable Windows TESTSIGNING mode
echo.
net session >nul 2>&1
if errorlevel 1 (
  echo ERROR: Please run as administrator.
  pause
  exit /b 1
)
bcdedit /set testsigning off
echo Restart Windows for the change to take effect.
pause
