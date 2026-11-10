@echo off
rem Imprompt setup for Windows - double-click this file. It opens this window and installs everything:
rem Git / Python / AutoHotkey / your AI CLI if missing, MCP, the global hotkey (Startup), then the sign-in window.
rem It runs the same one-line installer as the guide page, pinned to one release commit (the file cannot run other code).
rem Do not run as administrator. Safe to run again.
"%SystemRoot%\System32\chcp.com" 65001 >nul
title Imprompt setup
echo.
echo   Imprompt setup - keep this window open (about 2-10 minutes).
echo   If Windows asks for permission, click Yes. When the browser opens, approve the sign-in.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072; $global:ImpromptRC=1; $env:IMPROMPT_COMMIT='f87ddaee1165f76c5b7bf161fb0b0c897d2e8c8e'; irm https://raw.githubusercontent.com/seonoh/Imprompt/f87ddaee1165f76c5b7bf161fb0b0c897d2e8c8e/get.ps1 | iex; exit [int]$global:ImpromptRC"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo   Setup did not finish ^(code %RC%^). Read the lines marked with an X above, fix them, then double-click this file again.
  pause
  exit /b %RC%
)
echo   Done. Select text in any app and press Ctrl+Q. The pencil icon in the taskbar (under ^^) changes the hotkey or signs in.
echo   If a summary line above starts with !, do that one step (usually: pencil icon - Sign in...). You can close this window.
pause
