@echo off
rem Lancador do VoltaGoLive: Desativar
title VoltaGoLive - Desativar
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\VoltaGoLive.ps1" -Action Desativar
echo.
pause
