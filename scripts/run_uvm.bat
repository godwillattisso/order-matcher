@echo off
REM Day 4: compile and run the UVM testbench (tb_top + om_pkg).
REM Run in a Command Prompt AFTER settings64.bat.
REM Usage:  scripts\run_uvm.bat [test] [seed] [n_orders] [bp_percent]
REM   scripts\run_uvm.bat                            -> random_mix_test, seed 1, 1000 orders, no back-pressure
REM   scripts\run_uvm.bat random_mix_test 7          -> same test, random seed 7
REM   scripts\run_uvm.bat random_mix_test 7 500 25   -> 500 orders, trade_ready low 25% of cycles
setlocal
set TEST=%~1
if "%TEST%"=="" set TEST=random_mix_test
set SEED=%~2
if "%SEED%"=="" set SEED=1
set NORD=%~3
if "%NORD%"=="" set NORD=1000
set BP=%~4
if "%BP%"=="" set BP=0
pushd "%~dp0.."
if not exist model\ref_runner.exe (
  echo *** model\ref_runner.exe not found. Build it first in MSYS2 UCRT64:
  echo     cd /c/dev/order-matcher/model
  echo     g++ -std=c++14 -Wall -static -o ref_runner ref_runner.cpp ref_book.cpp
  popd
  exit /b 1
)
if not exist sim\uvm mkdir sim\uvm
cd sim\uvm
call xvlog -sv -L uvm -i ..\..\tb\uvm ..\..\rtl\book_side.sv ..\..\rtl\best_price.sv ..\..\rtl\match_engine.sv ..\..\tb\uvm\order_if.sv ..\..\tb\uvm\om_pkg.sv ..\..\tb\uvm\tb_top.sv
if errorlevel 1 goto fail
call xelab tb_top -L uvm -relax -timescale 1ns/1ps -debug typical -s uvm_sim
if errorlevel 1 goto fail
REM Quotes matter: without them, cmd splits each plusarg at "=" and xsim rejects it.
call xsim uvm_sim -runall -sv_seed %SEED% -testplusarg "UVM_TESTNAME=%TEST%" -testplusarg "N_ORDERS=%NORD%" -testplusarg "BP=%BP%"
popd
exit /b 0
:fail
echo.
echo *** COMPILE FAILED: read the first ERROR line above ***
popd
exit /b 1
