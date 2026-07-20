# Startup + trap vector for timer IRQ demo
    .section .text.start, "ax", @progbits
    .globl _start
    .type  _start, @function
_start:
    la   sp, _stack_top

    la   t0, _sidata
    la   t1, _sdata
    la   t2, _edata
1:
    bgeu t1, t2, 2f
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j    1b
2:
    la   t0, _sbss
    la   t1, _ebss
3:
    bgeu t0, t1, 4f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    3b
4:
    call main
.Lhalt:
    j    .Lhalt

    .globl trap_vector
    .type  trap_vector, @function
    .align 2
trap_vector:
    # Save everything the C handler may clobber (incl. callee-saved s0
    # that main uses as the irq_count base register).
    addi sp, sp, -64
    sw   ra,  60(sp)
    sw   t0,  56(sp)
    sw   t1,  52(sp)
    sw   t2,  48(sp)
    sw   a0,  44(sp)
    sw   a1,  40(sp)
    sw   a2,  36(sp)
    sw   a3,  32(sp)
    sw   a4,  28(sp)
    sw   a5,  24(sp)
    sw   a6,  20(sp)
    sw   a7,  16(sp)
    sw   s0,  12(sp)
    sw   s1,   8(sp)
    call timer_handler
    lw   s1,   8(sp)
    lw   s0,  12(sp)
    lw   a7,  16(sp)
    lw   a6,  20(sp)
    lw   a5,  24(sp)
    lw   a4,  28(sp)
    lw   a3,  32(sp)
    lw   a2,  36(sp)
    lw   a1,  40(sp)
    lw   a0,  44(sp)
    lw   t2,  48(sp)
    lw   t1,  52(sp)
    lw   t0,  56(sp)
    lw   ra,  60(sp)
    addi sp, sp, 64
    mret
