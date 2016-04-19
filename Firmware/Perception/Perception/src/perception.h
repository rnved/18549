/**
 * \file
 *
 * \brief Startup Template declarations
 *
 * Copyright (c) 2014-2016 Atmel Corporation. All rights reserved.
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
 * Support and FAQ: visit <a href="http://www.atmel.com/design-support/">Atmel
 * Support</a>
 */

#ifndef __PERCEPTION_H__
#define __PERCEPTION_H__

typedef enum {
	AD_TYPE_FLAGS = 01,
	AD_TYPE_COMPLETE_LIST_UUID = 0x03,
	AD_TYPE_COMPLETE_LOCAL_NAME = 0x09
} AD_TYPE;

typedef enum {
	PERCEPTION_DEV_UNCONNECTED,
	PERCEPTION_DEV_CONNECTING,
	PERCEPTION_DEV_CONNECTED,
	PERCEPTION_DEV_PAIRED,
	PERCEPTION_DEV_SERVICE_FOUND,
	PERCEPTION_DEV_CHAR_ALL_VIBE_FOUND
} PERCEPTION_DEV;

typedef struct gatt_perception_char_handler
{
	at_ble_handle_t start_handle;
	at_ble_handle_t end_handle;
	at_ble_handle_t char_handle1;
	at_ble_handle_t char_handle2;
	at_ble_handle_t char_handle3;
	at_ble_handle_t char_handle4;
	at_ble_status_t char_discovery;
	uint8_t *char_data1;
	uint8_t *char_data2;
	uint8_t *char_data3;
	uint8_t *char_data4;
}gatt_perception_char_handler_t;

#define PERCEPTION_ASCII_TO_DECIMAL_VALUE      ('0')

#define PERCEPTION_CONNECT_REQ_INTERVAL        (1000)

#define DISCOVER_SUCCESS				       (10)

#define PERCEPTION_CHAR_READ_INTERVAL          (500)

#define MAX_PERCEPTION_CHAR_SIZE               (1)

#define PERCEPTION_READ_LENGTH                 (1)

#define PERCEPTION_READ_OFFSET                 (0)




#endif /* __PERCEPTION_H__ */
