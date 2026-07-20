#include "uart.h"

/* Initialized global → lives in .data (copied ROM→RAM by crt0) */
static int g_magic = 42;

int main(void)
{
    int local = g_magic + 1; /* uses stack frame */

    puts_uart("Hello from C on RISC-V!\n");
    puts_uart("magic=");
    print_uint((unsigned)g_magic);
    puts_uart(" local=");
    print_uint((unsigned)local);
    putchar_uart('\n');

    return 0;
}
