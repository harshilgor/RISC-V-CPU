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
