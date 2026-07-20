#include "uart.h"

#define UART_BASE   0x10010000u
#define UART_TXDATA (*(volatile unsigned char *)(UART_BASE + 0))

void putchar_uart(char c)
{
    UART_TXDATA = (unsigned char)c;
}

void puts_uart(const char *s)
{
    while (*s)
        putchar_uart(*s++);
}

void print_uint(unsigned v)
{
    char buf[10];
    int i = 0;

    if (v == 0) {
        putchar_uart('0');
        return;
    }
    while (v > 0) {
        buf[i++] = (char)('0' + (v % 10));
        v /= 10;
    }
    while (i > 0)
        putchar_uart(buf[--i]);
}
