/* Linker script: code/rodata in ROM, .data/.bss + stack in RAM */
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

    /* Initialized data: live in RAM, load image kept in ROM after .rodata */
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

    /* Stack grows down from top of RAM */
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
