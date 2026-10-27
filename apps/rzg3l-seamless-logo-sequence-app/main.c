// SPDX-License-Identifier: MIT
/*
 * logo_sample_app - boot logo sample application
 *
 * Copyright (c) Renesas Electronics Corporation
 *
 * Shows a list of BMP images on the display through DRM/KMS, one after the
 * other at a fixed interval, and keeps the last one on screen until another
 * program - normally the compositor - replaces it.
 *
 * It is a reference for an application that continues a boot logo in Linux,
 * and deliberately generic: it runs on a stock BSP image as well as on one
 * built with meta-rzg3l-seamless-logo-sequence, where U-Boot has left the
 * display running and the kernel inherits it.  Nothing here depends on that
 * layer.
 *
 *   - The mode is chosen to suit the images: the connector's mode matching
 *     the first image, else its preferred mode.  With the layer the connector
 *     offers exactly one mode anyway, the one U-Boot drives.
 *   - An image that does not match the mode is centred, with what does not
 *     fit cropped and the rest black, or with --fit=scale scaled to fit.
 *   - BMP files may be 24 or 32 bpp, bottom-up or top-down, any width.
 *   - The dumb buffer is written row by row at its own pitch.
 *
 * Holding the last image: exiting would make the kernel take our framebuffer
 * off the display, leaving the screen dark until the compositor commits.
 * Instead, after the last image the program drops DRM master - which lets the
 * compositor become master - but keeps the device open, so the framebuffer
 * stays on screen.  It then watches the CRTC and exits once something else's
 * framebuffer is being scanned out; at that point closing the device no
 * longer touches the display.
 *
 * DRM master: the first process to open the DRM device becomes master, and
 * only the master may set modes.  The unit file orders this program before
 * weston.service with Type=notify, and the program reports readiness only
 * once it has dropped master, so weston starts right after the last image
 * instead of racing the first one.  Every failure path reports readiness
 * too: a boot logo must never hold the compositor back.
 */

#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <stddef.h>

#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>

#include <xf86drm.h>
#include <xf86drmMode.h>

#define PROGNAME		"logo_sample_app"

#define DEFAULT_MODULE		"rzg2l-du"
#define DEFAULT_INTERVAL_MS	1000u
#define DEFAULT_DEVICE_WAIT_MS	3000u
/* Give up holding the last image after this long; 0 means never. */
#define DEFAULT_HOLD_MAX_MS	60000u
/* How often to look whether someone else has taken the display over. */
#define HOLD_POLL_MS		100u

/* Refuse absurd BMP headers before multiplying them together. */
#define MAX_IMAGE_DIM		8192u

enum fit {
	FIT_CENTER,	/* 1:1, centred; crop what does not fit, black borders */
	FIT_SCALE,	/* scaled to fit, aspect ratio kept, black borders */
};

struct options {
	const char *module;
	unsigned int interval_ms;
	unsigned int hold_max_ms;
	unsigned int device_wait_ms;
	unsigned int mode_w, mode_h;	/* 0: choose from the first image */
	enum fit fit;
};

/* An image in XRGB8888, top-down, rows packed. */
struct image {
	uint32_t width, height;
	uint32_t *pixels;
};

struct buffer {
	uint32_t handle;
	uint32_t fb_id;
	uint32_t pitch;
	uint64_t size;
	uint8_t *map;
};

struct display {
	int fd;
	uint32_t connector_id;
	uint32_t crtc_id;
	drmModeModeInfo mode;
	struct buffer buf[2];
};

static volatile sig_atomic_t stop;

/* -------------------------------------------------------------------------
 * Helpers
 * ------------------------------------------------------------------------- */

static void logmsg(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

static void logmsg(const char *fmt, ...)
{
	va_list ap;

	fprintf(stderr, PROGNAME ": ");
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fputc('\n', stderr);
}

static uint64_t now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u;
}

/* Sleep until CLOCK_MONOTONIC reaches @deadline_ms, or a signal asks to stop. */
static void sleep_until(uint64_t deadline_ms)
{
	struct timespec ts;

	ts.tv_sec = (time_t)(deadline_ms / 1000u);
	ts.tv_nsec = (long)(deadline_ms % 1000u) * 1000000L;
	while (!stop &&
	       clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, NULL) == EINTR)
		;
}

static void on_signal(int sig)
{
	(void)sig;
	stop = 1;
}

static uint32_t rd16(const uint8_t *p)
{
	return (uint32_t)p[0] | (uint32_t)p[1] << 8;
}

static uint32_t rd32(const uint8_t *p)
{
	return (uint32_t)p[0] | (uint32_t)p[1] << 8 |
	       (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

/*
 * Report readiness to systemd (Type=notify), without linking libsystemd.
 * Idempotent: it is called from every exit path.
 */
static void notify_ready(void)
{
	static bool sent;
	struct sockaddr_un addr = { .sun_family = AF_UNIX };
	const char *path;
	socklen_t addrlen;
	size_t len;
	int fd;

	if (sent)
		return;
	sent = true;

	path = getenv("NOTIFY_SOCKET");
	if (!path || !*path)
		return;			/* not started by systemd */
	len = strlen(path);
	if (len >= sizeof(addr.sun_path))
		return;

	memcpy(addr.sun_path, path, len);
	if (addr.sun_path[0] == '@') {
		/* Abstract namespace: leading NUL, no trailing NUL. */
		addr.sun_path[0] = '\0';
		addrlen = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + len);
	} else {
		addrlen = (socklen_t)sizeof(addr);
	}

	fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return;
	if (sendto(fd, "READY=1\n", 8, MSG_NOSIGNAL,
		   (struct sockaddr *)&addr, addrlen) < 0)
		logmsg("sd_notify: %s", strerror(errno));
	close(fd);
}

/* -------------------------------------------------------------------------
 * BMP loading
 * ------------------------------------------------------------------------- */

/*
 * Load an uncompressed 24 or 32 bpp BMP into XRGB8888.  32 bpp files may use
 * BI_BITFIELDS as long as the masks describe that same layout.
 */
static int load_bmp(const char *path, struct image *img)
{
	uint8_t *data = NULL;
	uint32_t offset, hdr_size, bpp, comp, bytespp, stride, w, h, x, y;
	int32_t width, height;
	bool top_down;
	long size;
	FILE *fp;
	int ret = -1;

	memset(img, 0, sizeof(*img));

	fp = fopen(path, "rb");
	if (!fp) {
		logmsg("%s: %s", path, strerror(errno));
		return -1;
	}
	if (fseek(fp, 0, SEEK_END) != 0 || (size = ftell(fp)) < 0 ||
	    fseek(fp, 0, SEEK_SET) != 0) {
		logmsg("%s: cannot determine the file size", path);
		goto out;
	}
	if (size < 54) {
		logmsg("%s: too short for a BMP file", path);
		goto out;
	}
	data = malloc((size_t)size);
	if (!data || fread(data, 1, (size_t)size, fp) != (size_t)size) {
		logmsg("%s: cannot read the file", path);
		goto out;
	}

	if (data[0] != 'B' || data[1] != 'M') {
		logmsg("%s: not a BMP file", path);
		goto out;
	}

	offset = rd32(data + 10);
	hdr_size = rd32(data + 14);
	width = (int32_t)rd32(data + 18);
	height = (int32_t)rd32(data + 22);
	bpp = rd16(data + 28);
	comp = rd32(data + 30);

	if (hdr_size < 40) {
		logmsg("%s: unsupported BMP header (%u bytes)", path, hdr_size);
		goto out;
	}
	if (bpp != 24 && bpp != 32) {
		logmsg("%s: %u bpp; only 24 and 32 bpp are supported", path, bpp);
		goto out;
	}
	if (comp == 3 && bpp == 32 && size >= 66) {
		/* BI_BITFIELDS: masks follow the 40 byte header. */
		if (rd32(data + 54) != 0x00ff0000 || rd32(data + 58) != 0x0000ff00 ||
		    rd32(data + 62) != 0x000000ff) {
			logmsg("%s: only the XRGB8888 channel layout is supported",
			       path);
			goto out;
		}
	} else if (comp != 0) {
		logmsg("%s: compressed BMP (type %u) is not supported", path, comp);
		goto out;
	}
	if (width <= 0 || height == 0 || height == INT32_MIN) {
		logmsg("%s: invalid geometry %dx%d", path, width, height);
		goto out;
	}

	top_down = height < 0;
	w = (uint32_t)width;
	h = top_down ? (uint32_t)-height : (uint32_t)height;
	if (w > MAX_IMAGE_DIM || h > MAX_IMAGE_DIM) {
		logmsg("%s: %ux%u is larger than supported", path, w, h);
		goto out;
	}

	bytespp = bpp / 8;
	/* Rows are padded to a multiple of four bytes. */
	stride = (w * bytespp + 3u) & ~3u;
	if ((uint64_t)offset + (uint64_t)stride * h > (uint64_t)size) {
		logmsg("%s: truncated pixel data", path);
		goto out;
	}

	img->pixels = malloc((size_t)w * h * 4u);
	if (!img->pixels) {
		logmsg("%s: out of memory", path);
		goto out;
	}

	for (y = 0; y < h; y++) {
		const uint8_t *src = data + offset +
				     (size_t)stride * (top_down ? y : h - 1u - y);
		uint32_t *dst = img->pixels + (size_t)y * w;

		/* BMP stores B, G, R (, X) per pixel. */
		for (x = 0; x < w; x++, src += bytespp)
			dst[x] = 0xff000000u | (uint32_t)src[2] << 16 |
				 (uint32_t)src[1] << 8 | src[0];
	}

	img->width = w;
	img->height = h;
	ret = 0;
out:
	free(data);
	fclose(fp);
	return ret;
}

static void free_image(struct image *img)
{
	free(img->pixels);
	img->pixels = NULL;
}

/* -------------------------------------------------------------------------
 * Drawing
 * ------------------------------------------------------------------------- */

/* Fill @buf, @fbw x @fbh pixels at the buffer's pitch, with @img placed per @fit. */
static void draw_image(const struct buffer *buf, uint32_t fbw, uint32_t fbh,
		       const struct image *img, enum fit fit)
{
	uint32_t x, y;

	if (fit == FIT_SCALE && (img->width != fbw || img->height != fbh)) {
		/* The largest size that fits, keeping the aspect ratio. */
		uint32_t dw = fbw;
		uint32_t dh = (uint32_t)((uint64_t)img->height * fbw / img->width);
		uint32_t x0, y0;

		if (dh > fbh) {
			dh = fbh;
			dw = (uint32_t)((uint64_t)img->width * fbh / img->height);
		}
		if (dw == 0 || dh == 0) {
			for (y = 0; y < fbh; y++)
				memset(buf->map + (size_t)y * buf->pitch, 0, (size_t)fbw * 4u);
			return;
		}
		x0 = (fbw - dw) / 2u;
		y0 = (fbh - dh) / 2u;

		for (y = 0; y < fbh; y++) {
			uint32_t *row = (uint32_t *)(buf->map + (size_t)y * buf->pitch);
			const uint32_t *src;

			if (y < y0 || y >= y0 + dh) {
				memset(row, 0, (size_t)fbw * 4u);
				continue;
			}
			/* Nearest neighbour. */
			src = img->pixels +
			      (size_t)((uint64_t)(y - y0) * img->height / dh) * img->width;
			for (x = 0; x < fbw; x++)
				row[x] = (x < x0 || x >= x0 + dw) ? 0 :
					 src[(uint64_t)(x - x0) * img->width / dw];
		}
		return;
	}

	/* 1:1 and centred.  Offsets are negative when the image is larger. */
	{
		int64_t x0 = ((int64_t)fbw - img->width) / 2;
		int64_t y0 = ((int64_t)fbh - img->height) / 2;
		uint32_t sx = x0 < 0 ? (uint32_t)-x0 : 0;
		uint32_t dx = x0 > 0 ? (uint32_t)x0 : 0;
		uint32_t n = img->width - sx < fbw - dx ? img->width - sx : fbw - dx;

		for (y = 0; y < fbh; y++) {
			uint8_t *row = buf->map + (size_t)y * buf->pitch;
			int64_t sy = (int64_t)y - y0;

			if (sy < 0 || sy >= (int64_t)img->height) {
				memset(row, 0, (size_t)fbw * 4u);
				continue;
			}
			memset(row, 0, (size_t)dx * 4u);
			memcpy(row + (size_t)dx * 4u,
			       img->pixels + (size_t)sy * img->width + sx,
			       (size_t)n * 4u);
			memset(row + (size_t)(dx + n) * 4u, 0,
			       (size_t)(fbw - dx - n) * 4u);
		}
	}
}

/* -------------------------------------------------------------------------
 * DRM/KMS
 * ------------------------------------------------------------------------- */

/*
 * Open the DRM device driven by @module, waiting up to @wait_ms for it to
 * appear.  The nodes are opened directly rather than through drmOpen(): run
 * as root before the device exists, drmOpen() creates the missing
 * /dev/dri/card* nodes itself, leaving stale ones behind in /dev.
 */
static int open_drm(const char *module, unsigned int wait_ms)
{
	uint64_t deadline = now_ms() + wait_ms;
	char path[32];
	int fd, i;

	for (;;) {
		for (i = 0; i < 16; i++) {
			drmVersionPtr ver;
			bool match;

			snprintf(path, sizeof(path), "/dev/dri/card%d", i);
			fd = open(path, O_RDWR | O_CLOEXEC);
			if (fd < 0)
				continue;

			ver = drmGetVersion(fd);
			match = ver && strcmp(ver->name, module) == 0;
			drmFreeVersion(ver);
			if (match)
				return fd;
			close(fd);
		}

		if (stop || now_ms() >= deadline)
			return -1;
		usleep(20000);
	}
}

/*
 * Pick a mode.  A requested size (the -m option, or the first image) wins if
 * the connector offers it - the sink's preferred timing first, then the
 * highest refresh.  Otherwise the preferred mode, otherwise the first.
 */
static const drmModeModeInfo *pick_mode(const drmModeConnector *conn,
					uint32_t want_w, uint32_t want_h)
{
	const drmModeModeInfo *best = NULL;
	int i;

	for (i = 0; i < conn->count_modes; i++) {
		const drmModeModeInfo *m = &conn->modes[i];
		bool pref, best_pref;

		if (m->hdisplay != want_w || m->vdisplay != want_h)
			continue;
		if (!best) {
			best = m;
			continue;
		}
		pref = m->type & DRM_MODE_TYPE_PREFERRED;
		best_pref = best->type & DRM_MODE_TYPE_PREFERRED;
		if ((pref && !best_pref) ||
		    (pref == best_pref && m->vrefresh > best->vrefresh))
			best = m;
	}
	if (best)
		return best;

	for (i = 0; i < conn->count_modes; i++)
		if (conn->modes[i].type & DRM_MODE_TYPE_PREFERRED)
			return &conn->modes[i];

	return &conn->modes[0];
}

/* The CRTC to drive @conn with: the one it is on now, else the first possible. */
static uint32_t pick_crtc(int fd, const drmModeRes *res, const drmModeConnector *conn)
{
	drmModeEncoder *enc;
	uint32_t crtc = 0;
	int i, j;

	if (conn->encoder_id) {
		enc = drmModeGetEncoder(fd, conn->encoder_id);
		if (enc) {
			crtc = enc->crtc_id;
			drmModeFreeEncoder(enc);
		}
		if (crtc)
			return crtc;
	}

	for (i = 0; i < conn->count_encoders && !crtc; i++) {
		enc = drmModeGetEncoder(fd, conn->encoders[i]);
		if (!enc)
			continue;
		for (j = 0; j < res->count_crtcs; j++) {
			if (enc->possible_crtcs & (1u << j)) {
				crtc = res->crtcs[j];
				break;
			}
		}
		drmModeFreeEncoder(enc);
	}

	return crtc;
}

/* First connected connector with modes, its CRTC and a mode for @want_w x @want_h. */
static int setup_output(struct display *disp, uint32_t want_w, uint32_t want_h)
{
	drmModeRes *res;
	int i, ret = -1;

	res = drmModeGetResources(disp->fd);
	if (!res) {
		logmsg("drmModeGetResources: %s", strerror(errno));
		return -1;
	}

	for (i = 0; i < res->count_connectors && ret; i++) {
		drmModeConnector *conn = drmModeGetConnector(disp->fd, res->connectors[i]);
		uint32_t crtc;

		if (!conn)
			continue;
		if (conn->connection == DRM_MODE_CONNECTED && conn->count_modes > 0) {
			crtc = pick_crtc(disp->fd, res, conn);
			if (crtc) {
				disp->connector_id = conn->connector_id;
				disp->crtc_id = crtc;
				disp->mode = *pick_mode(conn, want_w, want_h);
				ret = 0;
			}
		}
		drmModeFreeConnector(conn);
	}

	drmModeFreeResources(res);
	if (ret)
		logmsg("no connected output with a usable CRTC");
	return ret;
}

static int create_buffer(int fd, uint32_t w, uint32_t h, struct buffer *buf)
{
	struct drm_mode_create_dumb create = { .width = w, .height = h, .bpp = 32 };
	struct drm_mode_map_dumb map = { 0 };
	struct drm_mode_destroy_dumb destroy = { 0 };
	void *ptr;

	memset(buf, 0, sizeof(*buf));

	if (drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) < 0) {
		logmsg("DRM_IOCTL_MODE_CREATE_DUMB: %s", strerror(errno));
		return -1;
	}
	buf->handle = create.handle;
	buf->pitch = create.pitch;
	buf->size = create.size;

	/* XRGB8888: depth 24, 32 bits per pixel. */
	if (drmModeAddFB(fd, w, h, 24, 32, buf->pitch, buf->handle, &buf->fb_id)) {
		logmsg("drmModeAddFB: %s", strerror(errno));
		goto err_destroy;
	}

	map.handle = buf->handle;
	if (drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &map) < 0) {
		logmsg("DRM_IOCTL_MODE_MAP_DUMB: %s", strerror(errno));
		goto err_rmfb;
	}
	ptr = mmap(NULL, buf->size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, map.offset);
	if (ptr == MAP_FAILED) {
		logmsg("mmap: %s", strerror(errno));
		goto err_rmfb;
	}
	buf->map = ptr;
	return 0;

err_rmfb:
	drmModeRmFB(fd, buf->fb_id);
err_destroy:
	destroy.handle = buf->handle;
	drmIoctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy);
	memset(buf, 0, sizeof(*buf));
	return -1;
}

static void on_page_flip(int fd, unsigned int seq, unsigned int sec,
			 unsigned int usec, void *data)
{
	(void)fd; (void)seq; (void)sec; (void)usec;
	*(bool *)data = true;
}

/* Flip to @fb_id and wait until it is on screen. */
static int page_flip(struct display *disp, uint32_t fb_id)
{
	drmEventContext ev = {
		.version = 2,
		.page_flip_handler = on_page_flip,
	};
	struct pollfd pfd = { .fd = disp->fd, .events = POLLIN };
	uint64_t deadline;
	bool done = false;

	if (drmModePageFlip(disp->fd, disp->crtc_id, fb_id,
			    DRM_MODE_PAGE_FLIP_EVENT, &done)) {
		logmsg("drmModePageFlip: %s", strerror(errno));
		return -1;
	}

	/* A flip completes at the next vblank; a second is generous. */
	deadline = now_ms() + 1000u;
	while (!done) {
		int64_t left = (int64_t)(deadline - now_ms());
		int r;

		if (left <= 0) {
			logmsg("timed out waiting for a page flip");
			return -1;
		}
		r = poll(&pfd, 1, (int)left);
		if (r < 0 && errno != EINTR) {
			logmsg("poll: %s", strerror(errno));
			return -1;
		}
		if (r > 0 && drmHandleEvent(disp->fd, &ev) != 0) {
			logmsg("drmHandleEvent failed");
			return -1;
		}
	}
	return 0;
}

/*
 * Put @fb_id up with a full modeset, then flip to it once more.  The flip is
 * a no-op on screen; it makes sure the plane really carries our buffer even
 * where a driver treats the first commit specially, as the boot logo
 * hand-over does.
 */
static int first_frame(struct display *disp, uint32_t fb_id)
{
	if (drmModeSetCrtc(disp->fd, disp->crtc_id, fb_id, 0, 0,
			   &disp->connector_id, 1, &disp->mode)) {
		logmsg("drmModeSetCrtc: %s%s", strerror(errno),
		       errno == EACCES ? " (is another program, such as the "
		       "compositor, already DRM master?)" : "");
		return -1;
	}
	return page_flip(disp, fb_id);
}

/*
 * Wait until the CRTC scans out something other than @fb_id - the compositor
 * has committed - or @max_ms passes (0: no limit), or a signal asks to stop.
 * The CRTC can be queried without being DRM master.
 */
static void hold_until_replaced(struct display *disp, uint32_t fb_id,
				unsigned int max_ms)
{
	uint64_t deadline = now_ms() + max_ms;

	while (!stop) {
		drmModeCrtc *crtc = drmModeGetCrtc(disp->fd, disp->crtc_id);
		uint32_t cur = crtc ? crtc->buffer_id : 0;

		drmModeFreeCrtc(crtc);
		if (cur != fb_id) {
			logmsg("display taken over, exiting");
			return;
		}
		if (max_ms && now_ms() >= deadline) {
			logmsg("nobody took the display over in %u ms, exiting", max_ms);
			return;
		}
		sleep_until(now_ms() + HOLD_POLL_MS);
	}
}

/* -------------------------------------------------------------------------
 * main
 * ------------------------------------------------------------------------- */

static void usage(FILE *fp)
{
	fprintf(fp,
"Usage: " PROGNAME " [options] IMAGE.bmp...\n"
"\n"
"Show the images one after the other through DRM/KMS, then keep the last one\n"
"on screen until another program replaces it.\n"
"\n"
"  -i, --interval=MS      time each image stays on screen (default %u)\n"
"  -t, --hold-max=MS      stop holding the last image after this long;\n"
"                         0 holds it until replaced (default %u)\n"
"  -m, --mode=WxH         use this mode if the display offers it\n"
"                         (default: the size of the first image)\n"
"  -f, --fit=center|scale place images that do not match the mode 1:1 and\n"
"                         centred, or scaled to fit (default center)\n"
"  -M, --module=NAME      DRM driver to use (default " DEFAULT_MODULE ")\n"
"  -d, --device-wait=MS   wait this long for the DRM device (default %u)\n"
"  -h, --help             show this help\n",
		DEFAULT_INTERVAL_MS, DEFAULT_HOLD_MAX_MS, DEFAULT_DEVICE_WAIT_MS);
}

static int parse_uint(const char *s, unsigned int *out)
{
	char *end;
	unsigned long v;

	errno = 0;
	v = strtoul(s, &end, 10);
	if (errno || end == s || *end || v > 0xffffffffUL)
		return -1;
	*out = (unsigned int)v;
	return 0;
}

static int parse_args(int argc, char **argv, struct options *opt)
{
	static const struct option longopts[] = {
		{ "interval",    required_argument, NULL, 'i' },
		{ "hold-max",    required_argument, NULL, 't' },
		{ "mode",        required_argument, NULL, 'm' },
		{ "fit",         required_argument, NULL, 'f' },
		{ "module",      required_argument, NULL, 'M' },
		{ "device-wait", required_argument, NULL, 'd' },
		{ "help",        no_argument,       NULL, 'h' },
		{ NULL, 0, NULL, 0 }
	};
	int c;

	while ((c = getopt_long(argc, argv, "i:t:m:f:M:d:h", longopts, NULL)) != -1) {
		switch (c) {
		case 'i':
			if (parse_uint(optarg, &opt->interval_ms))
				goto bad;
			break;
		case 't':
			if (parse_uint(optarg, &opt->hold_max_ms))
				goto bad;
			break;
		case 'm':
			if (sscanf(optarg, "%ux%u", &opt->mode_w, &opt->mode_h) != 2 ||
			    !opt->mode_w || !opt->mode_h)
				goto bad;
			break;
		case 'f':
			if (strcmp(optarg, "center") == 0)
				opt->fit = FIT_CENTER;
			else if (strcmp(optarg, "scale") == 0)
				opt->fit = FIT_SCALE;
			else
				goto bad;
			break;
		case 'M':
			opt->module = optarg;
			break;
		case 'd':
			if (parse_uint(optarg, &opt->device_wait_ms))
				goto bad;
			break;
		case 'h':
			usage(stdout);
			exit(0);
		default:
			usage(stderr);
			return -1;
		}
	}

	if (optind >= argc) {
		logmsg("no images given");
		usage(stderr);
		return -1;
	}
	return 0;

bad:
	logmsg("invalid value for -%c: '%s'", c, optarg);
	return -1;
}

int main(int argc, char **argv)
{
	struct options opt = {
		.module = DEFAULT_MODULE,
		.interval_ms = DEFAULT_INTERVAL_MS,
		.hold_max_ms = DEFAULT_HOLD_MAX_MS,
		.device_wait_ms = DEFAULT_DEVICE_WAIT_MS,
		.fit = FIT_CENTER,
	};
	struct display disp = { .fd = -1 };
	struct image img = { 0 };
	struct sigaction sa = { .sa_handler = on_signal };
	uint64_t start = 0;
	uint32_t want_w, want_h;
	int nimages, i, back = 0, ret = 1;

	if (parse_args(argc, argv, &opt)) {
		notify_ready();
		return 2;
	}
	nimages = argc - optind;

	sigemptyset(&sa.sa_mask);
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);

	/* The first image is loaded before the mode is picked: it sets the size. */
	if (load_bmp(argv[optind], &img)) {
		notify_ready();
		return 1;
	}
	want_w = opt.mode_w ? opt.mode_w : img.width;
	want_h = opt.mode_h ? opt.mode_h : img.height;

	disp.fd = open_drm(opt.module, opt.device_wait_ms);
	if (disp.fd < 0) {
		logmsg("no DRM device driven by '%s'", opt.module);
		goto out;
	}

	/*
	 * Ask for modes with their picture aspect ratio.  Without this the
	 * kernel strips the aspect ratio from the modes it reports and takes
	 * the mode handed back as having none - which a driver that pins its
	 * connector to one CEA mode, as the boot logo layer does, may reject
	 * as a different mode.  Harmless everywhere else.
	 */
	if (drmSetClientCap(disp.fd, DRM_CLIENT_CAP_ASPECT_RATIO, 1))
		logmsg("DRM_CLIENT_CAP_ASPECT_RATIO not supported, continuing");

	if (setup_output(&disp, want_w, want_h))
		goto out;
	if (disp.mode.hdisplay != want_w || disp.mode.vdisplay != want_h)
		logmsg("no %ux%u mode, using %ux%u", want_w, want_h,
		       disp.mode.hdisplay, disp.mode.vdisplay);

	for (i = 0; i < 2; i++)
		if (create_buffer(disp.fd, disp.mode.hdisplay, disp.mode.vdisplay,
				  &disp.buf[i]))
			goto out;

	for (i = 0; i < nimages && !stop; i++) {
		/* Always draw into the buffer that is not on screen. */
		struct buffer *buf = &disp.buf[back];

		if (i > 0 && load_bmp(argv[optind + i], &img)) {
			/* Skip it; the previous image stays up for its slot too. */
			continue;
		}

		draw_image(buf, disp.mode.hdisplay, disp.mode.vdisplay, &img, opt.fit);
		free_image(&img);

		if (i == 0) {
			if (first_frame(&disp, buf->fb_id))
				goto out;
			start = now_ms();
		} else {
			/* Flip on a fixed schedule, so loading time does not add up. */
			sleep_until(start + (uint64_t)i * opt.interval_ms);
			if (stop)
				break;
			if (page_flip(&disp, buf->fb_id))
				goto out;
		}
		back ^= 1;
	}

	/*
	 * The last image is up (it was drawn into the buffer before the final
	 * toggle).  Let go of DRM master so the compositor can take it, report
	 * readiness so systemd starts the compositor, and keep the image on
	 * screen until it is replaced.
	 */
	if (!stop) {
		if (drmDropMaster(disp.fd))
			logmsg("drmDropMaster: %s", strerror(errno));
		notify_ready();
		hold_until_replaced(&disp, disp.buf[back ^ 1].fb_id, opt.hold_max_ms);
	}
	ret = 0;

out:
	notify_ready();
	free_image(&img);
	/*
	 * Closing the device releases the buffers.  Once the compositor has
	 * committed, our framebuffer is no longer on any plane and this does
	 * not touch the display.
	 */
	for (i = 0; i < 2; i++)
		if (disp.buf[i].map)
			munmap(disp.buf[i].map, disp.buf[i].size);
	if (disp.fd >= 0)
		close(disp.fd);
	return ret;
}
