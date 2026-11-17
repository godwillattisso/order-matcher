@echo off
REM Unit test for uart_tx + uart_rx (tb_uart). Run in a Command Prompt AFTER settings64.bat.
REM Usage:  scripts\run_uart.bat
setlocal
pushd "%~dp0.."
if not exist sim\uart mkdir sim\uart
cd sim\uart
call xvlog -sv ..\..\rtl\uart_tx.sv ..\..\rtl\uart_rx.sv ..\..\tb\directed\tb_uart.sv
if errorlevel 1 goto fail
call xelab tb_uart -debug typical -s tb_uart_sim
if errorlevel 1 goto fail
call xsim tb_uart_sim -runall
popd
exit /b 0
:fail
echo.
echo *** COMPILE FAILED: read the first ERROR line above ***
popd
exit /b 1
