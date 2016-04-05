/**
* \file
*
* \brief Multi-Role/Multi-Connect Application
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
*    Atmel micro controller product.
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
*Support</a>
*/

/**
* \mainpage
* \section preface Preface
* This is the reference manual for the Multi-Role/Multi-Connect Application
*/
/*- Includes ---------------------------------------------------------------*/

#include <asf.h>
#include "platform.h"

#include "multirole_multiconnect.h"
#include "console_serial.h"
#include "ble_manager.h"
#include "at_ble_api.h"
#include "pxp_monitor.h"
#include "immediate_alert.h"
#include "timer_hw.h"


/** @brief APP_BAS_FAST_ADV between 0x0020 and 0x4000 in 0.625 ms units (20ms to 10.24s). */
#define APP_BAS_FAST_ADV				(100) //100 ms

/** @brief APP_BAS_ADV_TIMEOUT Advertising time-out between 0x0001 and 0x3FFF in seconds, 0x0000 disables time-out.*/
#define APP_BAS_ADV_TIMEOUT				(1000) // 100 Secs


extern ble_connected_dev_info_t ble_dev_info[BLE_MAX_DEVICE_CONNECTED];
extern uint8_t pxp_connect_request_flag;

bool volatile app_timer_done = false;

bool volatile timer_cb_done = false;


/**@brief Proximity Application initialization
* start the device scanning process
*/
static void pxp_app_init(void)
{
	at_ble_status_t scan_status;

	/* Initialize the scanning procedure */
	scan_status = gap_dev_scan();

	/* Check for scan status */
	if (scan_status == AT_BLE_INVALID_PARAM) {
		DBG_LOG("Scan parameters are invalid");
	} else if (scan_status == AT_BLE_FAILURE) {
		DBG_LOG("Scanning Failed Generic error");
	}
}

/* @brief timer call back for rssi update
* enable the flags to execute the application task
*
*/
static void timer_callback_handler(void)
{
	/* Stop the timer */
	hw_timer_stop();

	/* Enable the flag the serve the task */
	app_timer_done = true;
	if (!timer_cb_done)
	{
		timer_cb_done = true;
	}
	send_plf_int_msg_ind(USER_TIMER_CALLBACK, TIMER_EXPIRED_CALLBACK_TYPE_DETECT, NULL, 0);
}


int main(void)
{	
	#if SAMG55
	/* Initialize the SAM system. */
	sysclk_init();
	board_init();
	#elif SAM0
	system_init();
	#endif
	
	platform_driver_init();
	acquire_sleep_lock();
	
	/* Initialize serial console */
	serial_console_init();

	/* Initialize button */
	//button_init(button_cb);

	/* Initialize the hardware timer */
	hw_timer_init();

	/* Register the callback */
	hw_timer_register_callback(timer_callback_handler);

	/* initialize the BLE chip  and Set the device mac address */
	ble_device_init(NULL);
	
	pxp_monitor_init(NULL);

	DBG_LOG("Initializing Perception Central Application");

	/* Initialize the pxp service */
	pxp_app_init();
	
	register_hw_timer_start_func_cb((hw_timer_start_func_cb_t)hw_timer_start);
	register_hw_timer_stop_func_cb(hw_timer_stop);
	//register_peripheral_state_cb(peripheral_advertising_cb);

	while (1) {
		/* BLE Event Task */
		ble_event_task(BLE_EVENT_TIMEOUT);

		/* Application Task */
		if (app_timer_done) {
			if (pxp_connect_request_flag == PXP_DEV_CONNECTING) {
				at_ble_disconnected_t pxp_connect_request_fail;
				pxp_connect_request_fail.reason
					= AT_BLE_TERMINATED_BY_USER;
				pxp_connect_request_fail.handle = ble_dev_info[0].conn_info.handle;
				pxp_connect_request_flag = PXP_DEV_UNCONNECTED;
				if (at_ble_connect_cancel() == AT_BLE_SUCCESS) {
					DBG_LOG("Connection Timeout");
					pxp_disconnect_event_handler(
							&pxp_connect_request_fail);
				} else {
					DBG_LOG(
							"Unable to connect with device");
				}
			}

			app_timer_done = false;
		}
	}
}
