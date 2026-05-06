@echo off
setlocal

cd /d "%~dp0"
echo Starting Copilot LAN Bridge (default port, no auth)...
echo Trying LAN bind first: http://YOUR-LAN-IP:8787/

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0copilot-lan-bridge.ps1" -NoAuth

endlocal