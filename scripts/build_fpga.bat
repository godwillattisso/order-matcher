@echo off
REM Synthesis + place + route + bitstream (fpga\build.tcl). Takes a few minutes.
REM Run in a Command Prompt AFTER settings64.bat.   Usage:  scripts\build_fpga.bat
setlocal
pushd "%~dp0.."
if not exist build mkdir build
call vivado -mode batch -nojournal -log build\vivado.log -source fpga\build.tcl
if errorlevel 1 (
  echo.
  echo *** BUILD FAILED: open build\vivado.log and search for "ERROR:" ***
  popd
  exit /b 1
)
popd
exit /b 0
