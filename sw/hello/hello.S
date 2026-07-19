# UART hello for the teaching SoC
# UART @ 0x10010000  TXDATA=+0  TXSTATUS=+4
# ROM  @ 0x00000000
# RAM  @ 0x10000000

    .section .text.start, "ax", @progbits
    .globl _start
    .type  _start, @function
_start:
    # No stack needed for this bare-metal UART demo

    lui   t0, 0x10010          # t0 = UART base 0x10010000
    la    a0, msg              # a0 = pointer to string

1:
    lbu   t1, 0(a0)            # load next byte
    beq   t1, zero, 2f         # null terminator → done
    sb    t1, 0(t0)            # write TXDATA
    addi  a0, a0, 1
    jal   zero, 1b

2:
    # Spin forever (halt for the simulator)
    jal   zero, 2b

    .section .rodata
    .align 2
msg:
    .asciz "Hello from RISC-V!\n"
