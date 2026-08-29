@echo off
set SCRIPT_DIR=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%start-local-yolo-stack.ps1" %*
exit /b %ERRORLEVEL%

