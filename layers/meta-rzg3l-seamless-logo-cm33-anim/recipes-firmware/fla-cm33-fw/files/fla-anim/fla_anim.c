// SPDX-License-Identifier: BSD-3-Clause
/*
 * The CM33 writes no display register and does not access DDR, so it cannot
 * disturb U-Boot or Linux. It only changes two values in the anim body. The
 * VSPD reads them at the next frame start. Each value is one aligned 32-bit
 * word, so a frame sees either the old or the new value, and never tears.
 *
 *   WAIT  until U-Boot writes the magic
 *   PLAY  switch frames until Linux uses its own display list (then no more
 *         writes) or until the timeout (then hide Layer1)
 *   DONE  heartbeat only
 */
#include <stdint.h>
#include "fla_anim.h"
#include "fla_mailbox.h"

/* Overridable for a host test. */
#ifndef FLA_SRAM
#define FLA_SRAM(off)		((uintptr_t)FLA_SRAM_BASE + (off))
#endif
#ifndef FLA_PERI_RD32
/* The CM33 secure alias is at +0x3000_0000 (HWM Table 1.8-2). */
#define FLA_PERI_RD32(a)	(*(volatile uint32_t *)((uintptr_t)(a) + 0x30000000u))
#endif
#ifndef FLA_DSB
#define FLA_DSB()		__asm__ volatile("dsb" ::: "memory")
#endif

#define VSPD_DL_HDR_REF_ADDR0	(0x10870130u)
#define VSPD_WPF0_IRQ_STA	(0x1087004Cu)
#define WPF_IRQ_UND		(1u << 16)
#define DU_MSR0			(0x10890004u)
#define DU_MSR0_ST_PB_RUF	(1u << 21)
#define SYC_CNTCV_LO		(0x11001000u)	/* 24 MHz, started by BL2 */
#define SYC_CNTCV_HI		(0x11001004u)

#define MB	((volatile struct fla_mbox *)FLA_SRAM(FLA_MBOX_OFFSET))
#define BODY	((volatile struct fla_body_entry *)FLA_SRAM(FLA_BODY_OFFSET))

static enum fla_anim_state state;
static uint32_t ticks, frame, t0_ms, next_ms;

/* Copied once. Later mailbox changes have no effect. */
static uint32_t nframes, period_ms, flags, timeout_ms, show, hide, dl_lo, dl_hi;
static uint32_t frame_base, frame_bytes, loop_from;

static uint32_t frame_addr(uint32_t f)
{
	return frame_base + f * frame_bytes;
}

static void syc_stamp(volatile uint32_t *lo, volatile uint32_t *hi)
{
	uint32_t h, l;

	do {
		h = FLA_PERI_RD32(SYC_CNTCV_HI);
		l = FLA_PERI_RD32(SYC_CNTCV_LO);
	} while (h != FLA_PERI_RD32(SYC_CNTCV_HI));
	*lo = l;
	*hi = h;
}

static void finish(uint32_t reason, int hide_layer)
{
	if (hide_layer) {
		BODY[FLA_BODY_SRCRPF].val = hide;
		FLA_DSB();
	}
	syc_stamp(&MB->t_done_lo, &MB->t_done_hi);
	MB->done_reason = reason;
	FLA_DSB();
	MB->state = FLA_STATE_DONE;
	FLA_DSB();
	state = FLA_ANIM_DONE;
}

/* True after the first Linux commit. The anim body is then unused. */
static int linux_has_display(void)
{
	uint32_t ref = FLA_PERI_RD32(VSPD_DL_HDR_REF_ADDR0);

	MB->ref_addr = ref;
	return ref < dl_lo || ref >= dl_hi;
}

void fla_anim_init(void)
{
	volatile uint32_t *w = (volatile uint32_t *)FLA_SRAM(0);
	uint32_t i;

	for (i = 0; i < FLA_SRAM_SIZE / 4u; i++)
		w[i] = 0;
	MB->anim_version = FLA_ANIM_VERSION;
	FLA_DSB();
	MB->state = FLA_STATE_WAIT;
	FLA_DSB();
	ticks = 0;
	frame = 0;
	state = FLA_ANIM_WAIT;
}

static void wait_tick(uint32_t now_ms)
{
	if (MB->magic != FLA_MAGIC)
		return;
	FLA_DSB();	/* U-Boot wrote the other fields before the magic. */

	nframes = MB->nframes;
	period_ms = MB->period_ms;
	flags = MB->flags;
	timeout_ms = MB->timeout_ms;
	show = MB->srcrpf_show;
	hide = MB->srcrpf_hide;
	dl_lo = MB->dl_lo;
	dl_hi = MB->dl_hi;
	frame_base = MB->frame_base;
	frame_bytes = MB->frame_bytes;
	loop_from = MB->loop_from;
	/* The last frame must not wrap around the 32-bit address space. */
	if (MB->version != FLA_VERSION || nframes == 0u || loop_from >= nframes ||
	    (frame_bytes != 0u && nframes - 1u > (0xFFFFFFFFu - frame_base) / frame_bytes) ||
	    dl_lo >= dl_hi) {
		finish(FLA_DONE_PARAM, 0);
		return;
	}
	if (linux_has_display()) {
		finish(FLA_DONE_TAKEOVER, 0);
		return;
	}

	/* Frame address first: a frame that sees only this write is still correct. */
	frame = 0;
	BODY[FLA_BODY_FRAME].val = frame_addr(0);
	FLA_DSB();
	BODY[FLA_BODY_SRCRPF].val = show;
	FLA_DSB();
	syc_stamp(&MB->t_play_lo, &MB->t_play_hi);
	MB->frame = 0;
	MB->state = FLA_STATE_PLAY;
	FLA_DSB();
	t0_ms = now_ms;
	next_ms = now_ms + period_ms;
	state = FLA_ANIM_PLAY;
}

/* Read only. The status bits belong to U-Boot and Linux. */
static void sample_underruns(void)
{
	if (FLA_PERI_RD32(VSPD_WPF0_IRQ_STA) & WPF_IRQ_UND) {
		if (MB->und_ticks == 0u)
			MB->und_first = ticks;
		MB->und_ticks = MB->und_ticks + 1u;
	}
	if (FLA_PERI_RD32(DU_MSR0) & DU_MSR0_ST_PB_RUF) {
		if (MB->ruf_ticks == 0u)
			MB->ruf_first = ticks;
		MB->ruf_ticks = MB->ruf_ticks + 1u;
	}
}

static void play_tick(uint32_t now_ms)
{
	uint32_t f;

	if (linux_has_display()) {
		finish(FLA_DONE_TAKEOVER, 0);
		return;
	}
	sample_underruns();
	if (timeout_ms != 0u && (now_ms - t0_ms) >= timeout_ms) {
		finish(FLA_DONE_TIMEOUT, 1);
		return;
	}
	if (nframes < 2u || period_ms == 0u || (int32_t)(now_ms - next_ms) < 0)
		return;

	next_ms += period_ms;
	if ((int32_t)(now_ms - next_ms) >= 0)	/* late: skip, do not catch up */
		next_ms = now_ms + period_ms;

	f = frame + 1u;
	if (f >= nframes) {
		if (!(flags & FLA_F_LOOP)) {
			finish(FLA_DONE_END, !!(flags & FLA_F_HIDE_AT_END));
			return;
		}
		f = loop_from;
		MB->loops = MB->loops + 1u;
	}
	BODY[FLA_BODY_FRAME].val = frame_addr(f);
	FLA_DSB();
	frame = f;
	MB->frame = f;
	MB->frames_shown = MB->frames_shown + 1u;
}

void fla_anim_tick(uint32_t now_ms)
{
	if (state == FLA_ANIM_OFF)
		return;
	MB->heartbeat = ++ticks;

	switch (state) {
	case FLA_ANIM_WAIT:
		wait_tick(now_ms);
		break;
	case FLA_ANIM_PLAY:
		play_tick(now_ms);
		break;
	case FLA_ANIM_OFF:
	case FLA_ANIM_DONE:
	default:
		break;
	}
}

int fla_anim_active(void)
{
	return state == FLA_ANIM_PLAY;
}

enum fla_anim_state fla_anim_state(void)
{
	return state;
}
