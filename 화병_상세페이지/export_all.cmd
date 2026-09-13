@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0export_all.ps1" %*
if errorlevel 1 (
  echo.
  echo Export failed.
  pause
  exit /b 1
)
echo.
echo Export complete.
