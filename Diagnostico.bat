@echo off
rem Lancador do VoltaGoLive: Diagnostico
title VoltaGoLive - Diagnostico
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\VoltaGoLive.ps1" -Action Diagnostico
echo.
pause
