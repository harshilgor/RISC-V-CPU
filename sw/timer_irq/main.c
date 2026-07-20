#include "uart.h"

#define TIMER_MTIME    (*(volatile unsigned *)0x10020000u)
#define TIMER_MTIMECMP (*(volatile unsigned *)0x10020004u)

#define MSTATUS_MIE  (1u << 3)
#define MIE_MTIE     (1u << 7)

extern void trap_vector(void);

volatile unsigned irq_count;

void timer_handler(void)
{
    irq_count++;
    putchar_uart('!');
    if (irq_count >= 3)
        TIMER_MTIMECMP = 0xFFFFFFFFu; /* stop further IRQs */
    else
        TIMER_MTIMECMP = TIMER_MTIME + 80;
}

static inline void csr_write_mtvec(unsigned v)
{
    __asm__ volatile("csrw mtvec, %0" ::"r"(v));
}

static inline void csr_set_mie(unsigned v)
{
    __asm__ volatile("csrs mie, %0" ::"r"(v));
}

static inline void csr_set_mstatus(unsigned v)
{
    __asm__ volatile("csrs mstatus, %0" ::"r"(v));
}

static inline void csr_clear_mstatus(unsigned v)
{
    __asm__ volatile("csrc mstatus, %0" ::"r"(v));
}

int main(void)
{
    irq_count = 0;

    csr_write_mtvec((unsigned)(unsigned long)&trap_vector);

    puts_uart("timer irq demo\n");

    /* Arm timer after the banner so '!' cannot interleave */
    TIMER_MTIMECMP = TIMER_MTIME + 50;
    csr_set_mie(MIE_MTIE);
    csr_set_mstatus(MSTATUS_MIE);

    while (irq_count < 3)
        ;

    csr_clear_mstatus(MSTATUS_MIE);
    puts_uart("\ndone\n");
    return 0;
}
