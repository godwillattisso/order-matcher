@echo off
REM Loads build\order_matcher.bit onto the Basys3 (plugged in by USB and switched ON).
REM Run in a Command Prompt AFTER settings64.bat.   Usage:  scripts\program_fpga.bat
setlocal
pushd "%~dp0.."
if not exist build\order_matcher.bit (
  echo *** build\order_matcher.bit not found. Run scripts\build_fpga.bat first.
  popd
  exit /b 1
)
call vivado -mode batch -nojournal -log build\program.log -source fpga\program.tcl
if errorlevel 1 (
  echo.
  echo *** PROGRAMMING FAILED: is the board plugged in and switched on? See build\program.log ***
  popd
  exit /b 1
)
popd
exit /b 0
