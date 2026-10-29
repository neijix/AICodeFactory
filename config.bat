@echo off
rem config.bat - double-click to open the AICodeFactory settings page (aicf config).
rem Same as `bin\aicf.ps1 config`; extra arguments pass through (e.g. --no-open).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bin\aicf.ps1" config %*
if errorlevel 1 pause
