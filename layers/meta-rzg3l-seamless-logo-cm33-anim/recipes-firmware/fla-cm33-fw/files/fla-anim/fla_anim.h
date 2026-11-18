/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * Layer1 frame switching during the boot. Linked into fla-cm33-fw or into
 * lpdemo-cm33-fw (meta-rzg3l-lp-display).
 *
 * A non-blocking state machine driven by the caller's tick, so the CM33 can do
 * other work at the same time.
 */
#ifndef FLA_ANIM_H
#define FLA_ANIM_H

#include <stdint.h>
#include "fla_mailbox.h"

#define FLA_ANIM_VERSION	(0x00000400u)	/* 0.4.0 */

enum fla_anim_state {
	FLA_ANIM_OFF = FLA_STATE_OFF,
	FLA_ANIM_WAIT = FLA_STATE_WAIT,
	FLA_ANIM_PLAY = FLA_STATE_PLAY,
	FLA_ANIM_DONE = FLA_STATE_DONE,
};

/* Call before U-Boot runs: it clears the SRAM interface area. */
void fla_anim_init(void);

/* now_ms: ms since the firmware started. */
void fla_anim_tick(uint32_t now_ms);

/* Nonzero while Layer1 is shown. */
int fla_anim_active(void);

enum fla_anim_state fla_anim_state(void);

#endif /* FLA_ANIM_H */
