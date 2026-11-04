// SPDX-License-Identifier: GPL-2.0+
/*
 * Layer1 in the boot logo display lists, and the hand-over to the CM33.
 *
 * rzg2l_fla_setup() runs before the VSPD starts, because VSPD registers must
 * not change while it runs (HWM 9.4.3.2.3).
 *   header 0  Layer1 (RPF1), blended over the logo (RPF0). Written once.
 *   header 1  the anim body in SRAM, read at every frame start. Layer1 starts
 *             hidden. The CM33 shows it and switches the frames.
 *
 * rzg2l_fla_start() runs once the still logo is on screen, so loading the
 * frames does not delay the logo. The frames go to DDR 0x5A000000, inside the
 * area the kernel reserves for the boot logo.
 *
 * Environment (read once):
 *   fla_off=1       no Layer1
 *   fla_timeout_ms  overrides FLA_TIMEOUT_MS (0: no limit)
 *   fla_period_ms   overrides the time per frame
 */
#include <common.h>
#include <command.h>
#include <env.h>
#include <gzip.h>
#include "rzg2l_video.h"
#include "rzg2l_fla.h"
#include "fla_mailbox.h"
#include "fla_config.h"

/* VSPD register offsets in display list bodies (HWM 9.4.3.1) */
#define FLA_VI6_WPF0_SRCRPF		(0x1000u)
#define FLA_SRCRPF_RPF0_SUB		(1u << 0)
#define FLA_SRCRPF_RPF1_SUB		(1u << 2)
#define FLA_SRCRPF_VIRACT2_MST		(2u << 24)
#define FLA_VI6_DPR_RPF1_ROUTE		(0x2004u)
#define FLA_DPR_NODE_BRS_IN1		(39u)
#define FLA_VI6_RPF1(reg)		(0x0400u + (reg))
#define FLA_RPF_SRC_BSIZE		(0x00u)
#define FLA_RPF_SRC_ESIZE		(0x04u)
#define FLA_RPF_INFMT			(0x08u)
#define FLA_RPF_DSWAP			(0x0Cu)
#define FLA_RPF_LOC			(0x10u)
#define FLA_RPF_ALPH_SEL		(0x14u)
#define FLA_RPF_VRTCOL_SET		(0x18u)
#define FLA_RPF_MSK_CTRL		(0x1Cu)
#define FLA_RPF_CKEY_CTRL		(0x28u)
#define FLA_RPF_SRCM_PSTRIDE		(0x34u)
#define FLA_RPF_SRCM_ADDR_Y		(0x3Cu)
#define FLA_RPF_MULT_ALPH		(0x6Cu)
#define FLA_VI6_BRSB_CTRL		(0x3918u)
#define FLA_VI6_BRSB_BLD		(0x391Cu)

/* Same format, swap and blending as the boot logo on RPF0. */
#define FLA_INFMT_ARGB8888		(0x00010013u)
#define FLA_DSWAP_ARGB8888		(0x0000000Cu)
#define FLA_VRTCOL_OPAQUE		(0xFF000000u)
#define FLA_BRS_CTRL_RBC		(1u << 31)
#define FLA_BRS_CTRL_SRCSEL(n)		((n) << 16)
/* DST * (1 - SRCa) + SRC * SRCa, not premultiplied, as in Linux brx_configure_stream(). */
#define FLA_BRS_BLD_NORMAL		(0x323400FFu)
/*
 * Test frames are opaque: fixed alpha. The animation uses the pixel alpha, set
 * as Linux sets it (vsp1_rpf.c: ASEL_PACKED | AEXT_EXT, multiplier 255).
 */
#define FLA_ALPH_SEL_FIXED		(0x40040000u)
#define FLA_ALPH_SEL_PACKED		(0x00040000u)
#define FLA_MULT_ALPH_NONE		(0x000000FFu)
#define FLA_MULT_ALPH_A_RATIO		(0x000010FFu)

#define FLA_FRAME_BASE			(0x5A000000u)
#define FLA_AREA_BYTES			(0x05000000u)	/* display lists from 0x5F000000 */
#define FLA_TEST_STRIDE			(0x00100000u)	/* test frames: 1 MiB slots */
#define FLA_BPP				(4u)

/* Written by rzg3l-seamless-logo-cm33-anim-frames. */
#define FLA_FILE_LOAD			"ext4load mmc 0:2 0x48000000 boot/fla_anim.bin.gz"
#define FLA_FILE_LOAD_ADDR		(0x48000000u)
#define FLA_FILE_MAGIC			(0x46414C46u)	/* "FLAF" */
#define FLA_FILE_VERSION		(2u)
#define FLA_FILE_HDR_BYTES		(0x100u)
#define FLA_FILE_F_LOOP			(1u << 0)

struct fla_file_hdr {
	uint32_t magic;
	uint32_t version;
	uint32_t width;
	uint32_t height;
	uint32_t nframes;
	uint32_t period_ms;
	uint32_t flags;
	uint32_t frame_bytes;
	uint32_t loop_from;
};

#define FLA_WHITE			(0xFFFFFFFFu)
#define FLA_BLACK			(0xFF000000u)
#define FLA_GREY			(0xFF808080u)

#define DU_MSR0				(0x10890004u)
#define DU_MSR0_ST_PB_RUF		(1u << 21)

/* VI6_DL_HDR_REF_ADDR0 outside this range: Linux uses its own display list. */
#define FLA_DL_LO			(DISPLAY_LIST_HEADER_0)
#define FLA_DL_HI			(DISPLAY_LIST_HEADER_2 + 0x00100000u)

static struct {
	int ready;		/* Layer1 is in the display lists */
	const char *name;
	unsigned int w, h, x, y;
} fla;

static void body_add(display_body_t **b, uint32_t reg, uint32_t val)
{
	(*b)->address = reg;
	(*b)->data = val;
	(*b)++;
}

static uint32_t *test_frame(unsigned int i)
{
	return (uint32_t *)(uintptr_t)(FLA_FRAME_BASE + i * FLA_TEST_STRIDE);
}

static void pattern_still(void)
{
	uint32_t *fb = test_frame(0);
	unsigned int x, y;

	for (y = 0; y < fla.h; y++) {
		for (x = 0; x < fla.w; x++) {
			uint32_t c;

			if (x < 8 || y < 8 || x >= fla.w - 8 || y >= fla.h - 8)
				c = FLA_WHITE;
			else if ((((x - 8) / 30) + ((y - 8) / 30)) & 1)
				c = 0xFFFFB000u;
			else
				c = 0xFF303030u;
			fb[y * fla.w + x] = c;
		}
	}
}

/* A torn frame would show white and black in the column at once. */
static void pattern_sync(void)
{
	unsigned int f, x, y;

	for (f = 0; f < 2; f++) {
		uint32_t *fb = test_frame(f);
		uint32_t inside = f ? FLA_BLACK : FLA_WHITE;

		for (y = 0; y < fla.h; y++)
			for (x = 0; x < fla.w; x++)
				fb[y * fla.w + x] = (x < 8 || x >= fla.w - 8) ? FLA_GREY : inside;
	}
}

void rzg2l_fla_setup(display_header_t *hdr0, display_header_t *hdr1,
		     unsigned int hactive, unsigned int vactive)
{
	volatile struct fla_body_entry *anim =
		(volatile struct fla_body_entry *)(uintptr_t)(FLA_SRAM_BASE + FLA_BODY_OFFSET);
	const uint32_t hide = FLA_SRCRPF_VIRACT2_MST | FLA_SRCRPF_RPF0_SUB;
	int pixel_alpha = FLA_CFG_PATTERN == FLA_PATTERN_ANIM;
	display_body_t *b;

	fla.ready = 0;
	if (env_get_yesno("fla_off") == 1) {
		printf("fla: off (fla_off)\n");
		return;
	}

	switch (FLA_CFG_PATTERN) {
	case FLA_PATTERN_SYNC:
		fla.name = "sync";
		fla.w = 128;
		fla.h = vactive;
		fla.x = hactive * 3 / 4 - fla.w / 2;
		fla.y = 0;
		break;
	case FLA_PATTERN_STILL:
		fla.name = "still";
		fla.w = 256;
		fla.h = 256;
		break;
	default:
		fla.name = "anim";
		fla.w = FLA_CFG_ANIM_W;
		fla.h = FLA_CFG_ANIM_H;
		break;
	}
	if (hactive < fla.w || vactive < fla.h) {
		printf("fla: %ux%u Layer1 does not fit %ux%u\n", fla.w, fla.h, hactive, vactive);
		return;
	}
	if (FLA_CFG_PATTERN != FLA_PATTERN_SYNC) {
		unsigned int cy = FLA_CFG_PATTERN == FLA_PATTERN_ANIM ?
				  vactive * FLA_CFG_ANIM_Y_PERMILLE / 1000 : vactive * 3 / 4;

		fla.x = (hactive - fla.w) / 2;
		fla.y = cy > fla.h / 2 ? cy - fla.h / 2 : 0;
		if (fla.y + fla.h > vactive)
			fla.y = vactive - fla.h;
	}

	/* Appended after the boot logo entries of header 0. */
	b = (display_body_t *)(uintptr_t)(hdr0->list[0].pList + hdr0->list[0].num_bytes);
	body_add(&b, FLA_VI6_RPF1(FLA_RPF_SRC_BSIZE), (fla.w << 16) | fla.h);
	body_add(&b, FLA_VI6_RPF1(FLA_RPF_SRC_ESIZE), (fla.w << 16) | fla.h);
	body_add(&b, FLA_VI6_RPF1(FLA_RPF_INFMT), FLA_INFMT_ARGB8888);
	body_add(&b, FLA_VI6_RPF1(FLA_RPF_DSWAP), FLA_DSWAP_ARGB8888);
	body_add(&b, FLA_VI6_RPF1(FLA_RPF_LOC), (fla.x << 16) | fla.y);
	body_add(&b, FLA_VI6_RPF1(FLA_RPF_ALPH_SEL),
		 pixel_alpha ? FLA_ALPH_SEL_PACKED : FLA_ALPH_SEL_FIXED);
	body_add(&b, FLA_VI6_RPF1(FLA_RPF_VRTCOL_SET), FLA_VRTCOL_OPAQUE);
	body_add(&b, FLA_VI6_RPF1(FLA_RPF_MSK_CTRL), 0);
	body_add(&b, FLA_VI6_RPF1(FLA_RPF_CKEY_CTRL), 0);
	body_add(&b, FLA_VI6_RPF1(FLA_RPF_SRCM_PSTRIDE), ((fla.w * FLA_BPP) << 16) | fla.w);
	body_add(&b, FLA_VI6_RPF1(FLA_RPF_SRCM_ADDR_Y), FLA_FRAME_BASE);
	body_add(&b, FLA_VI6_RPF1(FLA_RPF_MULT_ALPH),
		 pixel_alpha ? FLA_MULT_ALPH_A_RATIO : FLA_MULT_ALPH_NONE);
	body_add(&b, FLA_VI6_DPR_RPF1_ROUTE, FLA_DPR_NODE_BRS_IN1);
	body_add(&b, FLA_VI6_BRSB_CTRL, FLA_BRS_CTRL_RBC | FLA_BRS_CTRL_SRCSEL(1));
	body_add(&b, FLA_VI6_BRSB_BLD, FLA_BRS_BLD_NORMAL);
	hdr0->list[0].num_bytes = (uint32_t)((uintptr_t)b - hdr0->list[0].pList);

	/* Hidden until the CM33 is ready to switch frames. */
	anim[FLA_BODY_FRAME].reg = FLA_VI6_RPF1(FLA_RPF_SRCM_ADDR_Y);
	anim[FLA_BODY_FRAME].val = FLA_FRAME_BASE;
	anim[FLA_BODY_SRCRPF].reg = FLA_VI6_WPF0_SRCRPF;
	anim[FLA_BODY_SRCRPF].val = hide;
	hdr1->list[1].num_bytes = FLA_BODY_ENTRIES * sizeof(struct fla_body_entry);
	hdr1->list[1].pList = FLA_SRAM_BASE + FLA_BODY_OFFSET;
	hdr1->num_list = 1;

	fla.ready = 1;
}

/* Returns the number of frames. 0: no animation, the still logo only. */
static unsigned int load_anim(uint32_t *base, uint32_t *bytes, uint32_t *loop_from,
			      ulong *period_ms, uint32_t *flags)
{
	const struct fla_file_hdr *h = (const struct fla_file_hdr *)(uintptr_t)FLA_FRAME_BASE;
	unsigned long len;

	if (run_command(FLA_FILE_LOAD, 0)) {
		printf("fla: no boot/fla_anim.bin.gz on mmc 0:2, Layer1 left out\n");
		return 0;
	}
	len = env_get_hex("filesize", 0);
	if (gunzip((void *)(uintptr_t)FLA_FRAME_BASE, FLA_AREA_BYTES,
		   (unsigned char *)(uintptr_t)FLA_FILE_LOAD_ADDR, &len)) {
		printf("fla: fla_anim.bin.gz does not inflate, Layer1 left out\n");
		return 0;
	}
	if (len < FLA_FILE_HDR_BYTES || h->magic != FLA_FILE_MAGIC ||
	    h->version != FLA_FILE_VERSION) {
		printf("fla: fla_anim.bin.gz is not an animation file (v%u), Layer1 left out\n",
		       FLA_FILE_VERSION);
		return 0;
	}
	if (h->width != fla.w || h->height != fla.h ||
	    h->frame_bytes != fla.w * fla.h * FLA_BPP) {
		printf("fla: fla_anim.bin.gz has %ux%u frames, U-Boot was built for %ux%u "
		       "(FLA_ANIM_SIZE), Layer1 left out\n", h->width, h->height, fla.w, fla.h);
		return 0;
	}
	if (h->nframes == 0 || h->loop_from >= h->nframes ||
	    len < FLA_FILE_HDR_BYTES + (unsigned long)h->nframes * h->frame_bytes) {
		printf("fla: fla_anim.bin.gz: %u frames (loop from %u) in %lu bytes, "
		       "Layer1 left out\n", h->nframes, h->loop_from, len);
		return 0;
	}
	*base = FLA_FRAME_BASE + FLA_FILE_HDR_BYTES;
	*bytes = h->frame_bytes;
	*loop_from = h->loop_from;
	*period_ms = h->period_ms;
	*flags = (h->flags & FLA_FILE_F_LOOP) ? FLA_F_LOOP : 0;
	return h->nframes;
}

void rzg2l_fla_start(void)
{
	volatile struct fla_mbox *mb =
		(volatile struct fla_mbox *)(uintptr_t)(FLA_SRAM_BASE + FLA_MBOX_OFFSET);
	const uint32_t hide = FLA_SRCRPF_VIRACT2_MST | FLA_SRCRPF_RPF0_SUB;
	ulong t0 = get_timer(0), timeout_ms, period_ms = FLA_CFG_PERIOD_MS;
	uint32_t base = (uint32_t)(uintptr_t)test_frame(0), bytes = FLA_TEST_STRIDE;
	uint32_t flags = 0, loop_from = 0, msr0, state;
	char loop[24] = "";
	unsigned int n;

	if (!fla.ready)
		return;

	switch (FLA_CFG_PATTERN) {
	case FLA_PATTERN_SYNC:
		pattern_sync();
		n = 2;
		flags = FLA_F_LOOP;
		break;
	case FLA_PATTERN_STILL:
		pattern_still();
		n = 1;
		period_ms = 0;
		break;
	default:
		n = load_anim(&base, &bytes, &loop_from, &period_ms, &flags);
		break;
	}
	if (n == 0)
		return;		/* no magic: the CM33 keeps Layer1 hidden */

	timeout_ms = env_get_ulong("fla_timeout_ms", 10, FLA_CFG_TIMEOUT_MS);
	period_ms = env_get_ulong("fla_period_ms", 10, period_ms);
	if (n == 1)
		period_ms = 0;
	msr0 = readl((void __iomem *)(uintptr_t)DU_MSR0);

	/*
	 * dcache_disable() flushes the frames to DDR for the VSPD. The SRAM writes
	 * then bypass the cache, so the CM33 sees the magic last.
	 */
	dcache_disable();
	mb->version = FLA_VERSION;
	mb->nframes = n;
	mb->frame_base = base;
	mb->frame_bytes = bytes;
	mb->loop_from = loop_from;
	mb->period_ms = period_ms;
	mb->flags = flags;
	mb->timeout_ms = timeout_ms;
	mb->srcrpf_show = hide | FLA_SRCRPF_RPF1_SUB;
	mb->srcrpf_hide = hide;
	mb->dl_lo = FLA_DL_LO;
	mb->dl_hi = FLA_DL_HI;
	mb->width = fla.w;
	mb->height = fla.h;
	mb->x = fla.x;
	mb->y = fla.y;
	dsb();
	mb->magic = FLA_MAGIC;
	dsb();
	state = mb->state;
	dcache_enable();

	if (flags & FLA_F_LOOP)
		snprintf(loop, sizeof(loop), " loop from %u", loop_from);
	printf("fla: %s: Layer1 %ux%u at (%u,%u), %u frame(s) every %lu ms%s, timeout %lu ms, "
	       "ready in %lu ms%s: CM33 state %u\n",
	       fla.name, fla.w, fla.h, fla.x, fla.y, n, period_ms, loop, timeout_ms, get_timer(t0),
	       (msr0 & DU_MSR0_ST_PB_RUF) ? ", DU PBUF underflow while loading" : "", state);
}
