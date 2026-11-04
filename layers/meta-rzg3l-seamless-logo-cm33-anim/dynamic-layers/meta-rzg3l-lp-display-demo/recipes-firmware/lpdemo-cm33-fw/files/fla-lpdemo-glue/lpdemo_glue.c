// SPDX-License-Identifier: BSD-3-Clause
/*
 * Connects the LowPower Display demo hooks (src/ext.h) to the animation.
 *
 * The animation ends when Linux takes over the display. That is long before
 * the demo can get an ENTER or DISP_RET request. An ENTER during the
 * animation is refused with BUSY.
 */
#include <stdint.h>
#include "ext.h"
#include "fla_anim.h"

void lpdemo_ext_init(void)
{
	fla_anim_init();
}

void lpdemo_ext_tick(uint32_t now_ms)
{
	fla_anim_tick(now_ms);
}

int lpdemo_ext_display_busy(void)
{
	return fla_anim_active();
}
