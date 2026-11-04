/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * Interface between U-Boot and the CM33 firmware, in the top 1 KiB of the BL22
 * SRAM area. U-Boot and the CM33 firmware are built from this same file. Bump
 * FLA_VERSION on any layout change.
 *
 *   0x59C00  anim body: display list body on the self-looping header 1, so
 *            the VSPD applies it at every frame start
 *   0x59D00  mailbox (struct fla_mbox)
 *
 * The frames are in DDR, one after the other: frame i is at
 * frame_base + i * frame_bytes. So their number is limited by the DDR area
 * U-Boot has for them, not by this SRAM area.
 *
 * Hand-over:
 *   1. The CM33 clears the area when it starts. SRAM keeps its content over a
 *      reset, so this removes the magic of the previous boot. BL2 starts the
 *      CM33 long before U-Boot runs.
 *   2. U-Boot fills the area and writes the magic last.
 *   3. The CM33 waits for the magic. Then it changes only the anim body
 *      values. The frames in DDR are read by the VSPD only.
 */
#ifndef FLA_MAILBOX_H
#define FLA_MAILBOX_H

#ifdef __UBOOT__
#include <linux/types.h>
#else
#include <stdint.h>
#endif

#define FLA_SRAM_BASE		(0x00059C00u)
#define FLA_SRAM_SIZE		(0x00000400u)	/* up to BL22_LIMIT 0x5A000 */
#define FLA_BODY_OFFSET		(0x000u)
#define FLA_MBOX_OFFSET		(0x100u)

#define FLA_MAGIC		(0x31414C46u)	/* "FLA1" */
#define FLA_VERSION		(2u)

/* VI6_RPF1_SRCM_ADDR_Y switches the frame, VI6_WPF0_SRCRPF shows / hides Layer1. */
struct fla_body_entry {
	uint32_t reg;
	uint32_t val;
};

#define FLA_BODY_FRAME		(0u)
#define FLA_BODY_SRCRPF		(1u)
#define FLA_BODY_ENTRIES	(2u)

/* fla_mbox.flags */
#define FLA_F_LOOP		(1u << 0)	/* restart at loop_from after the last frame */
#define FLA_F_HIDE_AT_END	(1u << 1)	/* without FLA_F_LOOP: hide Layer1 at the end */

/* fla_mbox.state (= enum fla_anim_state) */
#define FLA_STATE_OFF		(0u)
#define FLA_STATE_WAIT		(1u)	/* waiting for the magic */
#define FLA_STATE_PLAY		(2u)	/* Layer1 shown, frames switched */
#define FLA_STATE_DONE		(3u)	/* finished: no more LCDC / anim body access */

/* fla_mbox.done_reason */
#define FLA_DONE_NONE		(0u)
#define FLA_DONE_TAKEOVER	(1u)	/* Linux has its own display list */
#define FLA_DONE_TIMEOUT	(2u)	/* timeout_ms, Layer1 hidden */
#define FLA_DONE_END		(3u)	/* last frame of a non-looping animation */
#define FLA_DONE_PARAM		(4u)	/* mailbox from U-Boot not usable */

struct fla_mbox {
	/* U-Boot -> CM33, valid once magic == FLA_MAGIC */
	uint32_t magic;		/* 0x00 written last */
	uint32_t version;	/* 0x04 FLA_VERSION */
	uint32_t nframes;	/* 0x08 number of frames, at least 1 */
	uint32_t period_ms;	/* 0x0C time per frame (0: stay on frame 0) */
	uint32_t flags;		/* 0x10 FLA_F_* */
	uint32_t timeout_ms;	/* 0x14 hide Layer1 after this (0: until Linux takes over) */
	uint32_t srcrpf_show;	/* 0x18 VI6_WPF0_SRCRPF with RPF1 */
	uint32_t srcrpf_hide;	/* 0x1C VI6_WPF0_SRCRPF without RPF1 */
	uint32_t dl_lo;		/* 0x20 U-Boot display lists: [dl_lo, dl_hi). */
	uint32_t dl_hi;		/* 0x24 VI6_DL_HDR_REF_ADDR0 outside: Linux took over */
	uint32_t width;		/* 0x28 Layer1 size and position (information only) */
	uint32_t height;	/* 0x2C */
	uint32_t x;		/* 0x30 */
	uint32_t y;		/* 0x34 */
	uint32_t frame_base;	/* 0x38 DDR address of frame 0 */
	uint32_t frame_bytes;	/* 0x3C distance between two frames */

	/* CM33 -> */
	uint32_t state;		/* 0x40 FLA_STATE_* */
	uint32_t done_reason;	/* 0x44 FLA_DONE_* */
	uint32_t anim_version;	/* 0x48 FLA_ANIM_VERSION of the firmware */
	uint32_t heartbeat;	/* 0x4C ticks (10 ms) */
	uint32_t frame;		/* 0x50 frame on screen */
	uint32_t frames_shown;	/* 0x54 frame switches */
	uint32_t loops;		/* 0x58 */
	uint32_t ref_addr;	/* 0x5C last VI6_DL_HDR_REF_ADDR0 read */
	uint32_t t_play_lo;	/* 0x60 SYC (24 MHz, = CA55 CNTVCT) when Layer1 was shown */
	uint32_t t_play_hi;	/* 0x64 */
	uint32_t t_done_lo;	/* 0x68 SYC at DONE */
	uint32_t t_done_hi;	/* 0x6C */
	/*
	 * Diagnostics, sampled once per tick while PLAY: ticks with a VSPD underrun
	 * (VI6_WPF0_IRQ_STA.UND, sticky) or a DU PBUF underflow (DU_MSR0.ST_PB_RUF),
	 * and the heartbeat of the first one.
	 */
	uint32_t und_ticks;	/* 0x70 */
	uint32_t ruf_ticks;	/* 0x74 */
	uint32_t und_first;	/* 0x78 heartbeat, 0: never */
	uint32_t ruf_first;	/* 0x7C */

	/* U-Boot -> CM33, continued */
	uint32_t loop_from;	/* 0x80 FLA_F_LOOP restarts here, < nframes */
	uint32_t reserved1[3];	/* 0x84 */
};

_Static_assert(sizeof(struct fla_mbox) == 0x90, "fla_mbox layout");
_Static_assert(FLA_BODY_OFFSET + FLA_BODY_ENTRIES * sizeof(struct fla_body_entry) <=
	       FLA_MBOX_OFFSET, "anim body");
_Static_assert(FLA_MBOX_OFFSET + sizeof(struct fla_mbox) <= FLA_SRAM_SIZE, "mailbox");

#endif /* FLA_MAILBOX_H */
