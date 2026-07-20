#include "uart.h"

#define UART_TXDATA (*(volatile unsigned char *)0x10010000u)

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

void print_uint_padded(unsigned v, int width)
{
    char buf[10];
    int i = 0;
    int n;

    if (v == 0) {
        buf[i++] = '0';
    } else {
        while (v > 0) {
            buf[i++] = (char)('0' + (v % 10));
            v /= 10;
        }
    }
    for (n = i; n < width; ++n)
        putchar_uart(' ');
    while (i > 0)
        putchar_uart(buf[--i]);
}
