/* SPDX-License-Identifier: BSD-3-Clause */
/* Subset of lpdemo-cm33-fw/src/cm33.h (meta-rzg3l-lp-display). */
#ifndef CM33_H
#define CM33_H

#include <stdint.h>

/*
 * Addresses are written as the CA55 sees them, to match the HWM and the
 * TF-A/Linux sources. The CM33 sees peripherals at +0x3000_0000 (secure alias,
 * HWM Table 1.8-2). SRAM has the same address on both CPUs.
 */
#define CM33_PERI(ca55_addr)	((uintptr_t)(ca55_addr) + 0x30000000u)

static inline void mmio_write_32(uintptr_t a, uint32_t v) { *(volatile uint32_t *)a = v; }
static inline uint32_t mmio_read_32(uintptr_t a)          { return *(volatile uint32_t *)a; }

static inline void dsb(void) { __asm__ volatile("dsb" ::: "memory"); }
static inline void wfi(void) { __asm__ volatile("wfi" ::: "memory"); }
static inline void irq_enable(void)  { __asm__ volatile("cpsie i" ::: "memory"); }

/* System counter: 24 MHz, started by BL2, also the CA55 timer source. */
#define SYC_CNTCR		CM33_PERI(0x11000000u)	/* bit 0: EN */
#define SYC_CNTCV_LO		CM33_PERI(0x11001000u)
#define SYC_HZ			(24000000u)

static inline uint32_t syc_lo(void)
{
	return mmio_read_32(SYC_CNTCV_LO);
}

static inline int syc_running(void)
{
	return (mmio_read_32(SYC_CNTCR) & 1u) != 0u;
}

#define SCB_VTOR		(0xE000ED08u)
#define SCB_SHCSR		(0xE000ED24u)
#define SYST_CSR		(0xE000E010u)
#define SYST_RVR		(0xE000E014u)
#define SYST_CVR		(0xE000E018u)

#endif /* CM33_H */
