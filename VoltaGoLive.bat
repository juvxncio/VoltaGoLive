@echo off
rem Abre a janela do VoltaGoLive
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0scripts\Janela.ps1"
