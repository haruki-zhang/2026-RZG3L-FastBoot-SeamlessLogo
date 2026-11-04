# SPDX-License-Identifier: MIT
#
# The frames are made at build time into the file U-Boot loads (rzg2l_fla.c):
#
#   /boot/fla_anim.bin.gz, gzip of
#     0x000  header, 256 bytes, 32-bit little endian words: magic "FLAF",
#            version 2, width, height, nframes, period_ms, flags (bit 0: loop),
#            frame_bytes, loop_from (the loop restarts at this frame), then
#            zeros
#     0x100  the frames, ARGB8888, alpha not premultiplied
#
# U-Boot inflates the file directly to DDR 0x5A000000, where the VSPD reads
# the frames. So the frame layout is the layout the VSPD needs.
#
# Default (FLA_ANIM_FRAMES = ""): a 12-dot spinner with a percentage inside.
# The head steps by one dot per frame. The percentage is simulated: it counts
# from 1 % to 98 %, fast first, then slower, over FLA_ANIM_PROGRESS_S seconds.
# Then one turn of the spinner at 99 % loops until Linux takes over:
#
#   frames 0 .. N-1     1 % .. 98 %, played once, N = FLA_ANIM_PROGRESS_S / FLA_ANIM_PERIOD_MS
#   frames N .. N+11    99 %, loop_from = N
#
# The digits are fla_digits.png and fla_percent.png: Noto Sans Bold
# (SIL Open Font License 1.1, Google), white on transparent, rendered once at
# high resolution and scaled here to the frame size.
#
# Own frames: FLA_ANIM_FRAMES lists PNG files, played in that order.
# FLA_ANIM_LOOP_FROM is the frame the loop restarts at.

SUMMARY = "Layer1 animation frames for the RZ/G3L CM33 fast logo animation"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

FLA_ANIM_FRAMES ?= ""
FLA_ANIM_PROGRESS_S ?= "20"
FLA_ANIM_LOOP_FROM ?= "0"

# An absolute path is taken from the build host, a file name from FILESPATH.
SRC_URI = "${@' '.join('file://' + f for f in (d.getVar('FLA_ANIM_FRAMES') or '').split()) \
           or 'file://fla_digits.png file://fla_percent.png'}"

S = "${WORKDIR}"

COMPATIBLE_MACHINE = "smarc-rzg3l"
PACKAGE_ARCH = "${MACHINE_ARCH}"

# Made in bitbake's own Python, so no image library is needed.
INHIBIT_DEFAULT_DEPS = "1"
do_configure[noexec] = "1"

FLA_ANIM_BOOTDIR = "/boot"
FLA_ANIM_FILE = "fla_anim.bin.gz"

# Must match rzg2l_fla.c: DDR 0x5A000000 up to the display lists at 0x5F000000.
FLA_ANIM_AREA_BYTES = "83886080"

# The spinner: dots, and the last frames at 99 %.
FLA_SPINNER_DOTS = "12"

def fla_nframes(d):
    """(frames, loop_from) of the animation the settings describe."""
    own = (d.getVar('FLA_ANIM_FRAMES') or '').split()
    if own:
        return len(own), int(d.getVar('FLA_ANIM_LOOP_FROM'))
    n = max(1, round(float(d.getVar('FLA_ANIM_PROGRESS_S')) * 1000 /
                     int(d.getVar('FLA_ANIM_PERIOD_MS'))))
    return n + int(d.getVar('FLA_SPINNER_DOTS')), n

python () {
    import re

    m = re.fullmatch(r'([1-9][0-9]*)x([1-9][0-9]*)', d.getVar('FLA_ANIM_SIZE') or '')
    if not m:
        bb.fatal("FLA_ANIM_SIZE is '%s'; expected <width>x<height>, for example 256x256."
                 % d.getVar('FLA_ANIM_SIZE'))
    w, h = int(m.group(1)), int(m.group(2))
    for v in ('FLA_ANIM_PERIOD_MS', 'FLA_ANIM_LOOP', 'FLA_ANIM_LOOP_FROM'):
        if not (d.getVar(v) or '').isdigit():
            bb.fatal("%s is '%s'; expected a number" % (v, d.getVar(v)))
    own = (d.getVar('FLA_ANIM_FRAMES') or '').split()
    if not own:
        if not re.fullmatch(r'[0-9]+(\.[0-9]+)?', d.getVar('FLA_ANIM_PROGRESS_S') or '') \
                or float(d.getVar('FLA_ANIM_PROGRESS_S')) <= 0:
            bb.fatal("FLA_ANIM_PROGRESS_S is '%s'; expected the seconds from 1 %% to 99 %%, "
                     "for example 20." % d.getVar('FLA_ANIM_PROGRESS_S'))
        if int(d.getVar('FLA_ANIM_PERIOD_MS')) == 0:
            bb.fatal("FLA_ANIM_PERIOD_MS is 0; the spinner needs a time per frame.")
        if w != h:
            bb.fatal("FLA_ANIM_SIZE %dx%d: the spinner needs a square frame." % (w, h))
    n, loop_from = fla_nframes(d)
    if loop_from >= n:
        bb.fatal("FLA_ANIM_LOOP_FROM is %d; FLA_ANIM_FRAMES lists %d frames." % (loop_from, n))
    if (w * h * 4) % 256:
        bb.fatal("FLA_ANIM_SIZE %dx%d: a frame must be a multiple of 256 bytes "
                 "(width * height a multiple of 64)" % (w, h))
    if 0x100 + n * w * h * 4 > int(d.getVar('FLA_ANIM_AREA_BYTES')):
        bb.fatal("%d frames of %dx%d do not fit the %s bytes U-Boot has for them%s"
                 % (n, w, h, d.getVar('FLA_ANIM_AREA_BYTES'),
                    "" if own else "; shorten FLA_ANIM_PROGRESS_S or make "
                    "FLA_ANIM_PERIOD_MS or FLA_ANIM_SIZE smaller"))
}

def fla_png_rgba(path):
    """Returns (width, height, RGBA bytes). Only the PNG types the build allows."""
    import struct
    import zlib

    with open(path, 'rb') as f:
        data = f.read()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        bb.fatal("%s is not a PNG file" % path)
    pos, idat, ihdr = 8, bytearray(), None
    while pos < len(data):
        n, tag = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if tag == b'IHDR':
            ihdr = struct.unpack('>IIBBBBB', body)
        elif tag == b'IDAT':
            idat += body
        elif tag == b'IEND':
            break
    if ihdr is None:
        bb.fatal("%s: no IHDR" % path)
    w, h, depth, ctype, _, _, interlace = ihdr
    if depth != 8 or ctype not in (2, 6) or interlace:
        bb.fatal("%s: %d-bit colour type %d%s; expected 8-bit RGB (2) or RGBA (6), "
                 "not interlaced" % (path, depth, ctype, ", interlaced" if interlace else ""))
    bpp = 4 if ctype == 6 else 3
    raw = zlib.decompress(bytes(idat))
    stride = w * bpp
    if len(raw) != h * (stride + 1):
        bb.fatal("%s: image data is %d bytes, expected %d" % (path, len(raw), h * (stride + 1)))
    out = bytearray(h * stride)
    prev = bytearray(stride)
    for y in range(h):
        ft = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        if ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ft == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ft == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        elif ft != 0:
            bb.fatal("%s: bad PNG filter type %d in row %d" % (path, ft, y))
        out[y * stride:(y + 1) * stride] = line
        prev = line
    if bpp == 4:
        return w, h, bytes(out)
    rgba = bytearray(w * h * 4)
    for i in range(w * h):
        rgba[i * 4:i * 4 + 3] = out[i * 3:i * 3 + 3]
        rgba[i * 4 + 3] = 255
    return w, h, bytes(rgba)


def fla_resize_alpha(src, w, h, nw, nh):
    """Area-average scaling of a w x h alpha plane to nw x nh."""
    def taps(n, nn):
        s = n / nn
        out = []
        for i in range(nn):
            a, b = i * s, (i + 1) * s
            out.append([(j, (min(b, j + 1) - max(a, j)) / s)
                        for j in range(int(a), min(n, int(b) + 1)) if min(b, j + 1) > max(a, j)])
        return out
    tx, ty = taps(w, nw), taps(h, nh)
    rows = [[sum(src[y * w + j] * f for j, f in t) for t in tx] for y in range(h)]
    out = bytearray(nw * nh)
    for y, t in enumerate(ty):
        for x in range(nw):
            out[y * nw + x] = min(255, int(sum(rows[j][x] * f for j, f in t) + 0.5))
    return out

def fla_spinner_dots(k, size, dots):
    """Alpha plane of the spinner with its head on dot k. Dot 0 is at 12 o'clock,
    the head moves clockwise, the dots behind it fade."""
    import math

    ring, dot_r = size * 0.34, size * 0.055
    c = (size - 1) / 2.0
    alpha = bytearray(size * size)
    for j in range(dots):
        a = 255 * max(0.12, (1 - ((k - j) % dots) / dots) ** 1.6)
        th = 2 * math.pi * j / dots
        px, py = c + ring * math.sin(th), c - ring * math.cos(th)
        for y in range(max(0, int(py - dot_r - 2)), min(size, int(py + dot_r + 2) + 1)):
            for x in range(max(0, int(px - dot_r - 2)), min(size, int(px + dot_r + 2) + 1)):
                cov = min(1.0, max(0.0, dot_r + 0.5 - math.hypot(x - px, y - py)))
                v = int(a * cov + 0.5)
                if v > alpha[y * size + x]:
                    alpha[y * size + x] = v
    return alpha

def fla_glyphs(workdir, height):
    """{char: (width, alpha plane)} of "0".."9" and "%", scaled to height rows."""
    import os

    w, h, rgba = fla_png_rgba(os.path.join(workdir, 'fla_digits.png'))
    cw = round(w / 10 * height / h)
    plane = fla_resize_alpha(rgba[3::4], w, h, cw * 10, height)
    glyphs = {}
    for i in range(10):
        glyphs[str(i)] = (cw, b''.join(plane[y * cw * 10 + i * cw:y * cw * 10 + (i + 1) * cw]
                                       for y in range(height)))
    w, h, rgba = fla_png_rgba(os.path.join(workdir, 'fla_percent.png'))
    pw = round(w * height / h)
    glyphs['%'] = (pw, bytes(fla_resize_alpha(rgba[3::4], w, h, pw, height)))
    return glyphs

def fla_percent(i, n):
    """The simulated percentage of frame i of n: 1 .. 98, fast first, then slower."""
    return 1 + int(98 * (1 - (1 - i / n) ** 2))

def fla_spinner_frames(d):
    """Yields the alpha planes of the default animation (see the top of this file)."""
    size = int(d.getVar('FLA_ANIM_SIZE').split('x')[0])
    dots = int(d.getVar('FLA_SPINNER_DOTS'))
    nframes, n = fla_nframes(d)
    # Text inside the ring: the digits are about 13 % of the frame high.
    th = max(8, round(size * 0.15))
    glyphs = fla_glyphs(d.getVar('WORKDIR'), th)
    phases = [fla_spinner_dots(k, size, dots) for k in range(dots)]
    texts = {}
    for i in range(nframes):
        p = fla_percent(i, n) if i < n else 99
        if p not in texts:
            s = '%d%%' % p
            tw = sum(glyphs[ch][0] for ch in s)
            texts[p] = (tw, [b''.join(glyphs[ch][1][y * glyphs[ch][0]:(y + 1) * glyphs[ch][0]]
                                      for ch in s) for y in range(th)])
        tw, rows = texts[p]
        plane = bytearray(phases[i % dots])
        x0, y0 = (size - tw) // 2, (size - th) // 2
        for y, row in enumerate(rows):
            o = (y0 + y) * size + x0
            plane[o:o + tw] = bytes(max(a, b) for a, b in zip(plane[o:o + tw], row))
        yield plane

def fla_own_frames(d, w, h):
    """Yields the RGBA frames listed in FLA_ANIM_FRAMES."""
    import os

    for name in d.getVar('FLA_ANIM_FRAMES').split():
        path = name if os.path.isabs(name) else os.path.join(d.getVar('WORKDIR'), name)
        fw, fh, rgba = fla_png_rgba(path)
        if (fw, fh) != (w, h):
            bb.fatal("%s is %dx%d, but FLA_ANIM_SIZE is %dx%d" % (name, fw, fh, w, h))
        yield rgba

python do_compile() {
    import gzip
    import os
    import struct

    w, h = (int(v) for v in d.getVar('FLA_ANIM_SIZE').split('x'))
    period = int(d.getVar('FLA_ANIM_PERIOD_MS'))
    loop = int(d.getVar('FLA_ANIM_LOOP'))
    nframes, loop_from = fla_nframes(d)
    own = bool((d.getVar('FLA_ANIM_FRAMES') or '').split())

    hdr = struct.pack('<9I', 0x46414C46, 2, w, h, nframes, period,
                      1 if loop else 0, w * h * 4, loop_from)
    hdr += bytes(256 - len(hdr))
    out = os.path.join(d.getVar('B'), d.getVar('FLA_ANIM_FILE'))
    with gzip.GzipFile(out, 'wb', compresslevel=9, mtime=0) as f:
        f.write(hdr)
        if own:
            for rgba in fla_own_frames(d, w, h):
                # ARGB8888 as a little endian word is B, G, R, A in memory.
                frame = bytearray(len(rgba))
                frame[0::4] = rgba[2::4]
                frame[1::4] = rgba[1::4]
                frame[2::4] = rgba[0::4]
                frame[3::4] = rgba[3::4]
                f.write(frame)
        else:
            for alpha in fla_spinner_frames(d):
                frame = bytearray(b'\xff') * (w * h * 4)	# white
                frame[3::4] = alpha
                f.write(frame)
    bb.note("%s: %d frames of %dx%d, %d ms%s from frame %d, %d bytes raw, %d bytes compressed"
            % (d.getVar('FLA_ANIM_FILE'), nframes, w, h, period, " loop" if loop else "",
               loop_from, len(hdr) + nframes * w * h * 4, os.path.getsize(out)))
}
do_compile[vardeps] += "FLA_ANIM_SIZE FLA_ANIM_PERIOD_MS FLA_ANIM_LOOP FLA_ANIM_FRAMES \
                        FLA_ANIM_PROGRESS_S FLA_ANIM_LOOP_FROM FLA_SPINNER_DOTS"

do_install() {
    install -d ${D}${FLA_ANIM_BOOTDIR}
    install -m 0644 ${B}/${FLA_ANIM_FILE} ${D}${FLA_ANIM_BOOTDIR}/
}

FILES:${PN} = "${FLA_ANIM_BOOTDIR}/${FLA_ANIM_FILE}"
