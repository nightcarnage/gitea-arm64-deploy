@echo off
setlocal
title Save Revision
echo.
echo  ============================================
echo   Saving a revision
echo  ============================================
echo.
echo  Tip: save in your editor first - a revision
echo  only captures what is on disk.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Save-Revision.ps1" %*
echo.
echo  Press any key to close this window...
pause >nul
