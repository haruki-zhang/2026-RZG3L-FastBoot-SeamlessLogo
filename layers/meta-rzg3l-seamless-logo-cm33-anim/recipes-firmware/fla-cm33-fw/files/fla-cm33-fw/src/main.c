// SPDX-License-Identifier: BSD-3-Clause
/*
 * Animation-only CM33 firmware. With meta-rzg3l-lp-display, fla_anim.c is
 * linked into lpdemo-cm33-fw instead.
 *
 * SysTick only wakes the core. Time is taken from the system counter, so it
 * does not depend on the exact core clock.
 */
#include <stdint.h>
#include "cm33.h"
#include "fla_anim.h"

#define TICK_MS			(10u)
#define CM33_CLK_HZ		(200000000u)	/* P3 = PLL2 1600 MHz / 2 / 4 */

static volatile uint32_t g_ticks;

void SysTick_Handler(void)
{
	g_ticks++;
}

/* The 32-bit counter wraps after 178 s, so call this more often than that. */
static uint32_t now_ms_syc(void)
{
	static uint32_t last, acc, ms;
	static int started;
	uint32_t t = syc_lo();

	if (!started) {
		started = 1;
		last = t;
	}
	acc += t - last;
	last = t;
	while (acc >= SYC_HZ / 1000u) {
		acc -= SYC_HZ / 1000u;
		ms++;
	}
	return ms;
}

static void systick_start(uint32_t core_hz)
{
	mmio_write_32(SYST_RVR, core_hz / (1000u / TICK_MS) - 1u);
	mmio_write_32(SYST_CVR, 0);
	mmio_write_32(SYST_CSR, 7u);	/* processor clock, interrupt, enable */
}

int main(void)
{
	uint32_t last_tick = 0;
	int syc = syc_running();

	fla_anim_init();
	systick_start(CM33_CLK_HZ);
	if (syc)
		(void)now_ms_syc();		/* time 0 */
	irq_enable();

	for (;;) {
		uint32_t ticks;

		wfi();
		ticks = g_ticks;
		if (ticks == last_tick)
			continue;
		last_tick = ticks;
		fla_anim_tick(syc ? now_ms_syc() : ticks * TICK_MS);
	}
}
