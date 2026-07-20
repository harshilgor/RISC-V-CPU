#include "uart.h"

/* Initialized .data — copied ROM→RAM by crt0 */
static const char banner[] = "=== RISC-V SoC demo ===\n";

static unsigned fib(unsigned n)
{
    unsigned a = 0, b = 1, i, t;
    if (n == 0)
        return 0;
    for (i = 1; i < n; ++i) {
        t = a + b;
        a = b;
        b = t;
    }
    return b;
}

static unsigned sum_to(unsigned n)
{
    unsigned s = 0, i;
    for (i = 1; i <= n; ++i)
        s += i;
    return s;
}

static void print_fib_table(unsigned n)
{
    unsigned i;
    puts_uart("fib:");
    for (i = 0; i <= n; ++i) {
        putchar_uart(' ');
        print_uint(fib(i));
    }
    putchar_uart('\n');
}

static void print_squares(unsigned n)
{
    unsigned i;
    puts_uart("squares:");
    for (i = 1; i <= n; ++i) {
        putchar_uart(' ');
        print_uint(i * i);
    }
    putchar_uart('\n');
}

/* Tiny in-place bubble sort on a stack array */
static void sort_demo(void)
{
    int a[8] = {7, 2, 9, 1, 5, 3, 8, 4};
    int i, j, t;

    for (i = 0; i < 7; ++i) {
        for (j = 0; j < 7 - i; ++j) {
            if (a[j] > a[j + 1]) {
                t = a[j];
                a[j] = a[j + 1];
                a[j + 1] = t;
            }
        }
    }

    puts_uart("sorted:");
    for (i = 0; i < 8; ++i) {
        putchar_uart(' ');
        print_uint((unsigned)a[i]);
    }
    putchar_uart('\n');
}

int main(void)
{
    puts_uart(banner);
    print_fib_table(12);
    puts_uart("sum(1..20)=");
    print_uint(sum_to(20));
    putchar_uart('\n');
    print_squares(10);
    sort_demo();
    puts_uart("=== done ===\n");
    return 0;
}
