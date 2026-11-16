@echo off
REM Day 3: compile and run the match engine testbench (tb_engine).
REM Run in a Command Prompt AFTER settings64.bat.   Usage:
REM    scripts\run_engine.bat        -> run in the terminal, print PASS/FAIL
REM    scripts\run_engine.bat gui    -> open the waveform viewer instead
setlocal
pushd "%~dp0.."
if not exist sim\engine mkdir sim\engine
cd sim\engine
call xvlog -sv ..\..\rtl\book_side.sv ..\..\rtl\best_price.sv ..\..\rtl\match_engine.sv ..\..\tb\directed\tb_engine.sv
if errorlevel 1 goto fail
call xelab tb_engine -debug typical -s engine_sim
if errorlevel 1 goto fail
if /i "%~1"=="gui" (
  call xsim engine_sim -gui
) else (
  call xsim engine_sim -runall
)
popd
exit /b 0
:fail
echo.
echo *** COMPILE FAILED: read the first ERROR line above ***
popd
exit /b 1
