// SPDX-License-Identifier: BSD-3-Clause
/*
 * BL2 starts the CM33 in secure state with INITSVTOR = 0x20000, the load
 * address of the image. So the vector table must come first.
 */
#include <stdint.h>
#include "cm33.h"

extern uint32_t __bss_start, __bss_end, __stack_top;
extern int main(void);
extern void SysTick_Handler(void);

void Reset_Handler(void);
void Default_Handler(void);

__attribute__((section(".vectors"), used, aligned(128)))
const void *const g_vectors[16] = {
	&__stack_top,		/* initial MSP */
	Reset_Handler,
	Default_Handler,	/* NMI */
	Default_Handler,	/* HardFault */
	Default_Handler,	/* MemManage */
	Default_Handler,	/* BusFault */
	Default_Handler,	/* UsageFault */
	Default_Handler,	/* SecureFault */
	0, 0, 0,
	Default_Handler,	/* SVCall */
	Default_Handler,	/* DebugMonitor */
	0,
	Default_Handler,	/* PendSV */
	SysTick_Handler,
};

void Reset_Handler(void)
{
	uint32_t *p;

	/* BL2 loads the image into RAM, so .data is already in place. */
	for (p = &__bss_start; p < &__bss_end; p++)
		*p = 0;
	mmio_write_32(SCB_VTOR, (uint32_t)(uintptr_t)g_vectors);
	/* Separate fault handlers instead of HardFault, to ease debugging. */
	mmio_write_32(SCB_SHCSR, mmio_read_32(SCB_SHCSR) | (7u << 16));
	dsb();
	(void)main();
	for (;;)
		wfi();
}

/* Stop here for a debugger. The CA55 keeps running. */
void Default_Handler(void)
{
	for (;;)
		;
}
