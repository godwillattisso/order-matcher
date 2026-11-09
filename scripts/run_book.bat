@echo off
REM Day 2: compile and run the book testbench (tb_book).
REM Run in a Command Prompt AFTER settings64.bat.   Usage:
REM    scripts\run_book.bat        -> run in the terminal, print PASS/FAIL
REM    scripts\run_book.bat gui    -> open the waveform viewer instead
setlocal
pushd "%~dp0.."
if not exist sim\book mkdir sim\book
cd sim\book
call xvlog -sv ..\..\rtl\book_side.sv ..\..\rtl\best_price.sv ..\..\tb\directed\tb_book.sv
if errorlevel 1 goto fail
call xelab tb_book -debug typical -s book_sim
if errorlevel 1 goto fail
if /i "%~1"=="gui" (
  call xsim book_sim -gui
) else (
  call xsim book_sim -runall
)
popd
exit /b 0
:fail
echo.
echo *** COMPILE FAILED: read the first ERROR line above ***
popd
exit /b 1
