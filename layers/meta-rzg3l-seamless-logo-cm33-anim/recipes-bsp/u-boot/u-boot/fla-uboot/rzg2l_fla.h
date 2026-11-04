/* SPDX-License-Identifier: GPL-2.0+ */
/*
 *   rzg2l_fla_setup()  call before the VSPD starts
 *   rzg2l_fla_start()  call once the still logo is on screen
 */
#ifndef RZG2L_FLA_H
#define RZG2L_FLA_H

#include "rzg2l_video.h"

/* FLA_CFG_PATTERN, from FLA_TEST_PATTERN in the u-boot bbappend */
#define FLA_PATTERN_ANIM	0
#define FLA_PATTERN_STILL	1
#define FLA_PATTERN_SYNC	2

void rzg2l_fla_setup(display_header_t *hdr0, display_header_t *hdr1,
		     unsigned int hactive, unsigned int vactive);
void rzg2l_fla_start(void);

#endif /* RZG2L_FLA_H */
