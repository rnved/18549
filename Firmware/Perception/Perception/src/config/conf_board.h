/**
 * \file
 *
 * \brief SAM B11 Xplained Pro board configuration.
 *
 * Copyright (c) 2016 Atmel Corporation. All rights reserved.
 *
 * \asf_license_start
 *
 * \page License
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. The name of Atmel may not be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * 4. This software may only be redistributed and used in connection with an
 *    Atmel microcontroller product.
 *
 * THIS SOFTWARE IS PROVIDED BY ATMEL "AS IS" AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT ARE
 * EXPRESSLY AND SPECIFICALLY DISCLAIMED. IN NO EVENT SHALL ATMEL BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 * ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 * \asf_license_stop
 *
 */

/*
 * Support and FAQ: visit <a href="http://www.atmel.com/design-support/">Atmel Support</a>
 */

#ifndef CONF_BOARD_H_INCLUDED
#define CONF_BOARD_H_INCLUDED

#define VIBE1          PWM1
#define VIBE2          PWM2
#define VIBE3          PWM3
#define VIBE4          PWM4
#define VIBE1_PIN      PIN_LP_GPIO_17
#define VIBE2_PIN      PIN_LP_GPIO_18
#define VIBE3_PIN      PIN_LP_GPIO_19
#define VIBE4_PIN      PIN_LP_GPIO_20 
#define VIBE1_OUTMUX   PINMUX_MEGAMUX_FUNCTION_SELECT(MEGAMUX_PWM1_OUT)
#define VIBE2_OUTMUX   PINMUX_MEGAMUX_FUNCTION_SELECT(MEGAMUX_PWM2_OUT)
#define VIBE3_OUTMUX   PINMUX_MEGAMUX_FUNCTION_SELECT(MEGAMUX_PWM3_OUT)
#define VIBE4_OUTMUX   PINMUX_MEGAMUX_FUNCTION_SELECT(MEGAMUX_PWM4_OUT)

#endif /* CONF_BOARD_H_INCLUDED */
