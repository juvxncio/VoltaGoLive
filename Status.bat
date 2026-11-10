@echo off
rem Lancador do VoltaGoLive: Status
title VoltaGoLive - Status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\VoltaGoLive.ps1" -Action Status
echo.
pause
