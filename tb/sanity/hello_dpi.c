/* hello_dpi.c - Check 2: a tiny C function that SystemVerilog will call. */
#include "svdpi.h"

DPI_DLLESPEC int add_two(int a, int b) {
    return a + b;
}
