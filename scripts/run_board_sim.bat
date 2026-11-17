@echo off
REM Simulates the whole board design (top.sv) with a fake PC on the serial line (tb_board),
REM and compares the results with the C++ model. Run in a Command Prompt AFTER settings64.bat.
REM Usage:  scripts\run_board_sim.bat
setlocal
pushd "%~dp0.."
if not exist model\ref_runner.exe (
  echo *** model\ref_runner.exe not found. Build it first (see the Day 4 guide^).
  popd
  exit /b 1
)
if not exist sim\board mkdir sim\board
cd sim\board
call xvlog -sv ..\..\rtl\book_side.sv ..\..\rtl\best_price.sv ..\..\rtl\match_engine.sv ..\..\rtl\uart_rx.sv ..\..\rtl\uart_tx.sv ..\..\rtl\order_rx.sv ..\..\rtl\report_tx.sv ..\..\rtl\seg7_display.sv ..\..\rtl\top.sv ..\..\tb\directed\tb_board.sv
if errorlevel 1 goto fail
call xelab tb_board -debug typical -s tb_board_sim
if errorlevel 1 goto fail
call xsim tb_board_sim -runall
popd
exit /b 0
:fail
echo.
echo *** COMPILE FAILED: read the first ERROR line above ***
popd
exit /b 1
