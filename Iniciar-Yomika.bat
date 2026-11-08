@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0YomikaLocal.ps1"
if errorlevel 1 (
  echo.
  echo Yomika no pudo iniciarse. Revisa el mensaje anterior.
  pause
)
endlocal
