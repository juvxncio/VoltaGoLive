@echo off
rem Lancador do VoltaGoLive: Ativar
title VoltaGoLive - Ativar
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\VoltaGoLive.ps1" -Action Ativar
echo.
pause
