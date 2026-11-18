# BL2 loads only one CM33 firmware, so the animation is linked into the
# LowPower Display demo firmware through its hooks (src/ext.h).
FILESEXTRAPATHS:prepend := "${THISDIR}/files:${FLA_FW_FILESDIR}:"

SRC_URI += " \
    file://fla-anim \
    file://fla-lpdemo-glue \
"

LPDEMO_CM33_EXTRA_SRCS = " \
    ${WORKDIR}/fla-anim/fla_anim.c \
    ${WORKDIR}/fla-lpdemo-glue/lpdemo_glue.c \
"
LPDEMO_CM33_EXTRA_INCLUDES = "-I${WORKDIR}/fla-anim"
