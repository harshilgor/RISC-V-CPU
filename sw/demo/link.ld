/* Same memory map as other bare-metal apps */
MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 4K
}

SECTIONS
{
    .text : {
        *(.text.start)
        *(.text*)
    } > ROM

    .rodata : {
        *(.rodata*)
        *(.srodata*)
    } > ROM

    .data : {
        _sdata = .;
        *(.data*)
        *(.sdata*)
        _edata = .;
    } > RAM AT> ROM

    _sidata = LOADADDR(.data);

    .bss (NOLOAD) : {
        _sbss = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        _ebss = .;
    } > RAM

    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
