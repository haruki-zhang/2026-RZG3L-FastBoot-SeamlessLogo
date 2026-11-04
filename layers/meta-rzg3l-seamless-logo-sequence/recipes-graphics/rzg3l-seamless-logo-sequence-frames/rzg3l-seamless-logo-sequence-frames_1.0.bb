# SPDX-License-Identifier: MIT
#
# The frames stay editable BMP files. The build converts them to raw
# XRGB8888, gzip compressed, as /boot/fastlogo_<W>x<H>_NN.bin.gz.
# XRGB8888 is the frame buffer format, so U-Boot only has to unpack, not parse.
# Logo artwork is mostly flat colour, so gzip keeps the load short.
#
# U-Boot plays frames 00, 01, ... until a file is missing. See the guide,
# section 4.3, for your own frames.

SUMMARY = "Boot logo frames for the RZ/G3L U-Boot display driver"
DESCRIPTION = "Converts the boot logo artwork into gzip-compressed raw \
XRGB8888 frames and installs them where the U-Boot display driver looks for \
them."
HOMEPAGE = "https://github.com/renesas-rz"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# An absolute path is taken from the build host, a file name from FILESPATH.
SRC_URI = "${@' '.join('file://' + f for f in (d.getVar('RZG3L_LOGO_SEQUENCE_FRAMES') or '').split())}"

# U-Boot reads /boot on the rootfs partition.
RZG3L_LOGO_SEQUENCE_BOOTDIR = "/boot"

S = "${WORKDIR}"

# The frames depend on the display of this board, not only on the
# architecture.
COMPATIBLE_MACHINE = "smarc-rzg3l"
PACKAGE_ARCH = "${MACHINE_ARCH}"

# The conversion runs in bitbake's Python, so no toolchain is needed.
INHIBIT_DEFAULT_DEPS = "1"
do_configure[noexec] = "1"

# The U-Boot frame slots run from 0x58000000 to the display list headers at
# 0x5f000000.
RZG3L_LOGO_SEQUENCE_SLOT_BYTES = "117440512"

python () {
    import re

    # Both layers carry the same U-Boot and kernel patches. do_patch would
    # fail on the second copy.
    collections = (d.getVar('BBFILE_COLLECTIONS') or '').split()
    for other in ('meta-rzg3l-seamless-logo-still',):
        if other in collections:
            bb.fatal("meta-rzg3l-seamless-logo-sequence and %s cannot be used "
                     "together: both carry the seamless boot logo patch "
                     "series for u-boot and linux-renesas. Remove one of the "
                     "two layers from bblayers.conf." % other)

    if 'meta-rzg3l-fast-boot' in collections:
        bb.note("meta-rzg3l-seamless-logo-sequence is combined with "
                "meta-rzg3l-fast-boot; both append u-boot and "
                "linux-renesas, which is expected to work but is not the "
                "tested configuration.")

    res = d.getVar('RZG3L_LOGO_SEQUENCE_RESOLUTION') or ''
    m = re.fullmatch(r'([1-9][0-9]*)x([1-9][0-9]*)', res)
    if not m:
        bb.fatal("RZG3L_LOGO_SEQUENCE_RESOLUTION is '%s'; expected <width>x<height>, "
                 "for example 1920x1080." % res)

    frames = (d.getVar('RZG3L_LOGO_SEQUENCE_FRAMES') or '').split()
    if not frames:
        bb.fatal("RZG3L_LOGO_SEQUENCE_FRAMES is empty. To build an image without "
                 "boot logo frames set RZG3L_LOGO_SEQUENCE_PACKAGE = \"\" instead.")

    width, height = int(m.group(1)), int(m.group(2))
    room = int(d.getVar('RZG3L_LOGO_SEQUENCE_SLOT_BYTES')) // (width * height * 4)
    if len(frames) > room:
        bb.fatal("RZG3L_LOGO_SEQUENCE_FRAMES lists %d frames, but only %d frames of "
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
        # Also accept BI_BITFIELDS with B,G,R,X masks: most tools write 32 bpp
        # files that way.
        if compression not in (0, 3) or (compression == 3 and bpp != 32):
            bb.fatal("%s is compressed (BI_* %d); only BI_RGB is supported"
                     % (path, compression))
        if compression == 3:
            # The masks follow the 40-byte header, also in V4/V5 headers.
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

    res = d.getVar('RZG3L_LOGO_SEQUENCE_RESOLUTION')
    names = d.getVar('RZG3L_LOGO_SEQUENCE_FRAMES').split()

    for index, name in enumerate(names):
        # The file fetcher unpacks an absolute path relative to WORKDIR.
        src = os.path.join(workdir, name.lstrip('/'))
        if not os.path.exists(src):
            bb.fatal("%s is listed in RZG3L_LOGO_SEQUENCE_FRAMES but was not "
                     "fetched" % name)

        width, height, pixels = bmp_to_xrgb8888(src)

        # A frame of another size would be shown with the wrong stride.
        if '%dx%d' % (width, height) != res:
            bb.fatal("%s is %dx%d but RZG3L_LOGO_SEQUENCE_RESOLUTION is %s; every "
                     "frame must be drawn at the output resolution"
                     % (name, width, height, res))

        dst = os.path.join(outdir, 'fastlogo_%s_%02d.bin.gz' % (res, index))
        # mtime=0 and an empty stored filename keep the output reproducible.
        with open(dst, 'wb') as raw:
            with gzip.GzipFile(filename='', mode='wb', compresslevel=9,
                               fileobj=raw, mtime=0) as gz:
                gz.write(pixels)

        # U-Boot rejects a frame that is not exactly one slot. Find it here,
        # not after writing the board.
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
    install -d ${D}${RZG3L_LOGO_SEQUENCE_BOOTDIR}
    install -m 0644 ${B}/frames/fastlogo_${RZG3L_LOGO_SEQUENCE_RESOLUTION}_*.bin.gz \
        ${D}${RZG3L_LOGO_SEQUENCE_BOOTDIR}/

    # U-Boot stops at the first missing number, so a gap would cut the
    # sequence short without an error.
    n=0
    for name in ${RZG3L_LOGO_SEQUENCE_FRAMES}; do
        f=$(printf '%s/fastlogo_%s_%02d.bin.gz' ${D}${RZG3L_LOGO_SEQUENCE_BOOTDIR} ${RZG3L_LOGO_SEQUENCE_RESOLUTION} $n)
        [ -e "$f" ] || bbfatal "frame $n ($name) was not installed as $f"
        n=$(expr $n + 1)
    done
}

FILES:${PN} = "${RZG3L_LOGO_SEQUENCE_BOOTDIR}/fastlogo_*.bin.gz"

# Not ELF: nothing to strip, split or check for libraries.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
EXCLUDE_FROM_SHLIBS = "1"
