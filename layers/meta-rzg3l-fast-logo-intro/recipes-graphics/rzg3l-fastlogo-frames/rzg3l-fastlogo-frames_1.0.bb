# SPDX-License-Identifier: MIT
#
# The frames U-Boot plays at power-on.
#
# The artwork is kept as editable BMP files and converted at build time into
# what the U-Boot display driver loads: raw XRGB8888, gzip compressed, one file
# per frame, installed as /boot/fastlogo_<W>x<H>_NN.bin.gz. Raw XRGB8888 is the
# frame buffer's own format, so U-Boot inflates each frame straight into the
# reserved region with no image parsing; the compression keeps the read short
# because boot artwork is mostly flat colour.
#
# U-Boot plays frames 00, 01, ... until the next file is missing, so the
# number of frames is simply the length of RZG3L_FASTLOGO_FRAMES. To use your
# own artwork, set in local.conf
#
#   RZG3L_FASTLOGO_FRAMES = "/path/to/a.bmp /path/to/b.bmp"
#
# or bbappend this recipe with FILESEXTRAPATHS:prepend and list plain file
# names. See the layer README, section IV.

SUMMARY = "Boot logo frames for the RZ/G3L U-Boot display driver"
DESCRIPTION = "Converts the boot logo artwork into gzip-compressed raw \
XRGB8888 frames and installs them where the U-Boot display driver looks for \
them."
HOMEPAGE = "https://github.com/renesas-rz"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# One entry per frame. An absolute path is fetched from the build host as is;
# anything else is looked up in FILESPATH.
SRC_URI = "${@' '.join('file://' + f for f in (d.getVar('RZG3L_FASTLOGO_FRAMES') or '').split())}"

# Where U-Boot reads them from: /boot on the rootfs partition, next to Image
# and the device tree.
RZG3L_FASTLOGO_BOOTDIR = "/boot"

S = "${WORKDIR}"

# The artwork belongs to this board's display, not merely to its architecture.
COMPATIBLE_MACHINE = "smarc-rzg3l"
PACKAGE_ARCH = "${MACHINE_ARCH}"

# Nothing is compiled: the conversion runs inside bitbake's own Python, so this
# recipe needs no toolchain at all.
INHIBIT_DEFAULT_DEPS = "1"
do_configure[noexec] = "1"

# U-Boot's frame slots run from 0x58000000 up to its display list headers at
# 0x5f000000 (drivers/video/rzg2l).
RZG3L_FASTLOGO_SLOT_BYTES = "117440512"

python () {
    import re

    # --- Layers carrying the same U-Boot and kernel series. Together, every
    #     patch would be offered twice and do_patch fails on the second copy.
    collections = (d.getVar('BBFILE_COLLECTIONS') or '').split()
    for other in ('meta-rzg3l-fast-logo', 'meta-rzg3l-fast-anime-logo'):
        if other in collections:
            bb.fatal("meta-rzg3l-fast-logo-intro and %s cannot be used "
                     "together: both carry the seamless boot logo patch "
                     "series for u-boot and linux-renesas. Remove one of the "
                     "two layers from bblayers.conf." % other)

    if 'meta-rzg3l-fast-boot-base' in collections:
        bb.note("meta-rzg3l-fast-logo-intro is combined with "
                "meta-rzg3l-fast-boot-base; both append u-boot and "
                "linux-renesas, which is expected to work but is not the "
                "tested configuration.")

    res = d.getVar('RZG3L_FASTLOGO_RESOLUTION') or ''
    m = re.fullmatch(r'([1-9][0-9]*)x([1-9][0-9]*)', res)
    if not m:
        bb.fatal("RZG3L_FASTLOGO_RESOLUTION is '%s'; expected <width>x<height>, "
                 "for example 1920x1080." % res)

    frames = (d.getVar('RZG3L_FASTLOGO_FRAMES') or '').split()
    if not frames:
        bb.fatal("RZG3L_FASTLOGO_FRAMES is empty. To build an image without "
                 "boot logo frames set RZG3L_FASTLOGO_PACKAGE = \"\" instead.")

    width, height = int(m.group(1)), int(m.group(2))
    room = int(d.getVar('RZG3L_FASTLOGO_SLOT_BYTES')) // (width * height * 4)
    if len(frames) > room:
        bb.fatal("RZG3L_FASTLOGO_FRAMES lists %d frames, but only %d frames of "
                 "%s fit in the area U-Boot reserves for them."
                 % (len(frames), room, res))
}

python do_compile() {
    import os
    import struct
    import gzip
    import shutil

    def bmp_to_xrgb8888(path):
        """Return (width, height, XRGB8888 top-down pixel data)."""
        with open(path, 'rb') as f:
            data = f.read()

        if len(data) < 54 or data[0:2] != b'BM':
            bb.fatal("%s is not a BMP file" % path)

        offset, = struct.unpack_from('<I', data, 10)
        width, height = struct.unpack_from('<ii', data, 18)
        bpp, = struct.unpack_from('<H', data, 28)
        compression, = struct.unpack_from('<I', data, 30)

        if bpp not in (24, 32):
            bb.fatal("%s is %d bpp; only uncompressed 24 or 32 bpp BMP is "
                     "supported" % (path, bpp))
        # BI_RGB, or BI_BITFIELDS for 32 bpp files whose masks say B,G,R,X in
        # memory - which is what most tools write for 32 bpp.
        if compression not in (0, 3) or (compression == 3 and bpp != 32):
            bb.fatal("%s is compressed (BI_* %d); only BI_RGB is supported"
                     % (path, compression))
        if compression == 3:
            # The masks follow a 40 byte header, and sit at the same offsets
            # inside the V4/V5 headers.
            masks = struct.unpack_from('<III', data, 54)
            if masks != (0x00ff0000, 0x0000ff00, 0x000000ff):
                bb.fatal("%s uses channel masks R=%08x G=%08x B=%08x; only "
                         "the XRGB8888 layout is supported" % ((path,) + masks))
        if width <= 0 or height == 0:
            bb.fatal("%s has a nonsensical geometry %dx%d"
                     % (path, width, height))

        # A negative height means the rows are already top-down.
        top_down = height < 0
        height = abs(height)

        bytespp = bpp // 8
        # BMP scanlines are padded to a 4 byte boundary.
        stride = ((width * bytespp) + 3) & ~3
        if len(data) < offset + stride * height:
            bb.fatal("%s is truncated: need %d bytes, have %d"
                     % (path, offset + stride * height, len(data)))

        row_bytes = width * 4
        out = bytearray(row_bytes * height)

        for y in range(height):
            src_y = y if top_down else (height - 1 - y)
            src = data[offset + src_y * stride:
                       offset + src_y * stride + width * bytespp]
            dst = y * row_bytes
            # BMP stores B,G,R(,X); XRGB8888 little-endian is B,G,R,X in memory.
            out[dst + 0:dst + row_bytes:4] = src[0::bytespp]
            out[dst + 1:dst + row_bytes:4] = src[1::bytespp]
            out[dst + 2:dst + row_bytes:4] = src[2::bytespp]
            out[dst + 3:dst + row_bytes:4] = b'\xff' * width

        return width, height, bytes(out)

    workdir = d.getVar('WORKDIR')
    outdir = os.path.join(workdir, 'frames')
    shutil.rmtree(outdir, ignore_errors=True)
    os.makedirs(outdir)

    res = d.getVar('RZG3L_FASTLOGO_RESOLUTION')
    names = d.getVar('RZG3L_FASTLOGO_FRAMES').split()

    for index, name in enumerate(names):
        # The file fetcher unpacks an absolute path relative to WORKDIR.
        src = os.path.join(workdir, name.lstrip('/'))
        if not os.path.exists(src):
            bb.fatal("%s is listed in RZG3L_FASTLOGO_FRAMES but was not "
                     "fetched" % name)

        width, height, pixels = bmp_to_xrgb8888(src)

        # U-Boot drives exactly one mode, and a frame of any other size would
        # be scanned out with the wrong stride.
        if '%dx%d' % (width, height) != res:
            bb.fatal("%s is %dx%d but RZG3L_FASTLOGO_RESOLUTION is %s; every "
                     "frame must be drawn at the output resolution"
                     % (name, width, height, res))

        dst = os.path.join(outdir, 'fastlogo_%s_%02d.bin.gz' % (res, index))
        # mtime=0 and an empty stored filename keep the output reproducible.
        with open(dst, 'wb') as raw:
            with gzip.GzipFile(filename='', mode='wb', compresslevel=9,
                               fileobj=raw, mtime=0) as gz:
                gz.write(pixels)

        # U-Boot rejects a frame that does not inflate to exactly one slot.
        # Catch it here rather than at the far end of a flash-and-boot cycle.
        expected = width * height * 4
        with gzip.open(dst, 'rb') as gz:
            actual = len(gz.read())
        if actual != expected:
            bb.fatal("%s decompresses to %d bytes, expected %d"
                     % (dst, actual, expected))

        bb.note("%s -> %s (%d -> %d bytes)"
                % (name, os.path.basename(dst), expected,
                   os.path.getsize(dst)))
}

do_install() {
    install -d ${D}${RZG3L_FASTLOGO_BOOTDIR}
    install -m 0644 ${B}/frames/fastlogo_${RZG3L_FASTLOGO_RESOLUTION}_*.bin.gz \
        ${D}${RZG3L_FASTLOGO_BOOTDIR}/

    # U-Boot stops at the first missing number, so a gap would silently cut
    # the intro short.
    n=0
    for name in ${RZG3L_FASTLOGO_FRAMES}; do
        f=$(printf '%s/fastlogo_%s_%02d.bin.gz' ${D}${RZG3L_FASTLOGO_BOOTDIR} ${RZG3L_FASTLOGO_RESOLUTION} $n)
        [ -e "$f" ] || bbfatal "frame $n ($name) was not installed as $f"
        n=$(expr $n + 1)
    done
}

FILES:${PN} = "${RZG3L_FASTLOGO_BOOTDIR}/fastlogo_*.bin.gz"

# Read straight off the block device by the bootloader: nothing here is ELF, so
# there is nothing to strip, debug-split or resolve shared libraries for.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
EXCLUDE_FROM_SHLIBS = "1"
