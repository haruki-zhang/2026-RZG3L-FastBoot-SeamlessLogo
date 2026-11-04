/*
 * BL2 copies 192 KiB to BL22_BASE (0x20000) and starts the CM33 there.
 *
 *   0x20000..0x4FFFF  vectors, code and data: the part BL2 copies
 *   ..0x59BFF         .bss and stack
 *   0x59C00..0x59FFF  U-Boot <-> CM33 interface (fla_mailbox.h)
 */
MEMORY {
	RAM (rwx) : ORIGIN = 0x00020000, LENGTH = 0x0003A000
}

ENTRY(Reset_Handler)

SECTIONS
{
	.vectors : {
		KEEP(*(.vectors))
	} > RAM

	.text : {
		*(.text*)
		*(.rodata*)
		. = ALIGN(4);
	} > RAM

	.data : {
		*(.data*)
		. = ALIGN(4);
		__load_end = .;
	} > RAM

	.bss (NOLOAD) : {
		__bss_start = .;
		*(.bss*)
		*(COMMON)
		. = ALIGN(4);
		__bss_end = .;
	} > RAM

	.stack (NOLOAD) : {
		. = ALIGN(8);
		. = . + 0x2000;
		__stack_top = .;
	} > RAM

	/DISCARD/ : {
		*(.ARM.exidx*)
		*(.ARM.extab*)
		*(.note*)
		*(.interp)
		*(.dyn*)
		*(.gnu.hash)
		*(.rel.dyn)
		*(.comment)
	}
}

ASSERT(g_vectors == 0x00020000, "vector table is not at BL22_BASE 0x20000")
ASSERT(__load_end <= 0x00050000, "loaded image exceeds the 192 KiB BL2 reads")
ASSERT(__stack_top <= 0x00059C00, "image + stack overlap the fast logo animation area 0x59C00")
