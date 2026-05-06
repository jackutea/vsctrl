@echo off
setlocal

cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
	echo [ERROR] Node.js not found. Please install Node.js 20+ first.
	exit /b 1
)

if not exist "%~dp0node_modules" (
	echo Installing dependencies...
	call npm install
	if errorlevel 1 exit /b 1
)

echo Building TypeScript...
call npm run build
if errorlevel 1 exit /b 1

echo Starting Copilot LAN Bridge (Node.js TypeScript, default no auth)...
echo Trying LAN bind first: http://YOUR-LAN-IP:8787/
node "%~dp0dist\server.js" --port 8787 --bindHost + --noAuth %*

set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%