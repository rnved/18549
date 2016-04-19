/**
 * \file
 *
 * \brief BLE Startup Template
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
 * Support and FAQ: visit <a href="http://www.atmel.com/design-support/">Atmel
 * Support</a>
 */

/**
 * \mainpage
 * \section preface Preface
 * This is the reference manual for the Startup Template
 */
/*- Includes ---------------------------------------------------------------*/
#include <asf.h>
#include "platform.h"
#include "at_ble_api.h"
#include "console_serial.h"
#include "timer_hw.h"
#include "ble_manager.h"
#include "ble_utils.h"
#include "button.h"
#include "perception.h"


at_ble_addr_t perception_reporter_address;

extern volatile uint8_t scan_response_count;
extern at_ble_scan_info_t scan_info[MAX_SCAN_DEVICE];

volatile uint8_t perception_state_flag = PERCEPTION_DEV_UNCONNECTED;
volatile bool vibe1_char_found = false;
volatile bool vibe2_char_found = false;
volatile bool vibe3_char_found = false;
volatile bool vibe4_char_found = false;

extern ble_connected_dev_info_t ble_dev_info[BLE_MAX_DEVICE_CONNECTED];

bool volatile timer_done = false;

gatt_perception_char_handler_t perception_handle =
{0, 0, 0, 0, 0, 0, AT_BLE_INVALID_PARAM, NULL, NULL, NULL, NULL};
uint8_t perception_char_data1[MAX_PERCEPTION_CHAR_SIZE];
uint8_t perception_char_data2[MAX_PERCEPTION_CHAR_SIZE];
uint8_t perception_char_data3[MAX_PERCEPTION_CHAR_SIZE];
uint8_t perception_char_data4[MAX_PERCEPTION_CHAR_SIZE];

uint8_t vibe1_duty;
uint8_t vibe2_duty;
uint8_t vibe3_duty;
uint8_t vibe4_duty;


/* Function Prototypes */
at_ble_status_t perception_start_scan(void);
at_ble_status_t perception_connect_request(at_ble_scan_info_t *scan_buffer,uint8_t index);
at_ble_status_t perception_service_discover(at_ble_handle_t handle);


/* PWM Initialization */
static void configure_pwm(void)
{
	struct pwm_config cfg_vibe1;
	struct pwm_config cfg_vibe2;
	struct pwm_config cfg_vibe3;
	struct pwm_config cfg_vibe4;

	pwm_get_config_defaults(&cfg_vibe1);
	pwm_get_config_defaults(&cfg_vibe2);
	pwm_get_config_defaults(&cfg_vibe3);
	pwm_get_config_defaults(&cfg_vibe4);

	vibe1_duty = 0;
	vibe2_duty = 0;
	vibe3_duty = 0;
	vibe4_duty = 0;

	cfg_vibe1.duty_cycle = 0;
	cfg_vibe1.pin_number_pad = VIBE1_PIN;
	cfg_vibe1.pinmux_sel_pad = VIBE1_OUTMUX;
	cfg_vibe2.duty_cycle = 0;
	cfg_vibe2.pin_number_pad = VIBE2_PIN;
	cfg_vibe2.pinmux_sel_pad = VIBE2_OUTMUX;
	cfg_vibe3.duty_cycle = 0;
	cfg_vibe3.pin_number_pad = VIBE3_PIN;
	cfg_vibe3.pinmux_sel_pad = VIBE3_OUTMUX;
	cfg_vibe4.duty_cycle = 0;
	cfg_vibe4.pin_number_pad = VIBE4_PIN;
	cfg_vibe4.pinmux_sel_pad = VIBE4_OUTMUX;

	pwm_init(VIBE1, &cfg_vibe1);
	pwm_init(VIBE2, &cfg_vibe2);
	pwm_init(VIBE3, &cfg_vibe3);
	pwm_init(VIBE4, &cfg_vibe4);

	pwm_enable(VIBE1);
	pwm_enable(VIBE2);
	pwm_enable(VIBE3);
	pwm_enable(VIBE4);
}


/**@brief Perception Application initialization
 * Start the device scanning process
 */
static void perception_app_init(void)
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

at_ble_status_t perception_start_scan(void)
{
	//char index_value;
	// NOT SURE IF NEEDED
	hw_timer_stop();
	//do
	//{
		//DBG_LOG("Select [r] to Reconnect or [s] Scan");
		//index_value = getchar_b11();
		//DBG_LOG("%c", index_value);
	//}	while (!((index_value == 'r') || (index_value == 's')));
	
	/*if(index_value == 'r') {
		if (gap_dev_connect(&perception_reporter_address) == AT_BLE_SUCCESS) {
			DBG_LOG("Perception Re-Connect request sent");
			perception_state_flag = PERCEPTION_DEV_CONNECTING;
			hw_timer_start(PERCEPTION_CONNECT_REQ_INTERVAL);
			return AT_BLE_SUCCESS;
		} else {
			DBG_LOG("Perception Re-Connect request send failed");
		}
	}*/
	//else if(index_value == 's') {
		return gap_dev_scan();
	//}
	//return AT_BLE_FAILURE;
}

at_ble_status_t perception_connect_request(at_ble_scan_info_t *scan_buffer,
uint8_t index)
{
	memcpy((uint8_t *)&perception_reporter_address,
	(uint8_t *)&scan_buffer[index].dev_addr,
	sizeof(at_ble_addr_t));

	if (gap_dev_connect(&perception_reporter_address) == AT_BLE_SUCCESS) {
		DBG_LOG("Perception Connect request sent");
		perception_state_flag = PERCEPTION_DEV_CONNECTING;
		hw_timer_start(PERCEPTION_CONNECT_REQ_INTERVAL);
		return AT_BLE_SUCCESS;
	} else {
		DBG_LOG("Perception Connect request send failed");
	}

	return AT_BLE_FAILURE;
}

at_ble_status_t perception_service_discover(at_ble_handle_t handle)
{
	at_ble_status_t status;
	status = at_ble_primary_service_discover_all(
		handle,
		GATT_DISCOVERY_STARTING_HANDLE,
		GATT_DISCOVERY_ENDING_HANDLE);
	if (status == AT_BLE_SUCCESS) {
		DBG_LOG_DEV("GATT Discovery request started ");
	} else {
		DBG_LOG("GATT Discovery request failed");
	}
	
	return status;
}


/* Callback functions */

/* Callback registered for AT_BLE_SCAN_REPORT event from stack */
static at_ble_status_t ble_scan_report_app_event(void *param)
{
	uint8_t scan_device[MAX_SCAN_DEVICE];
	uint8_t perception_scan_device_count = 0;
	uint8_t scanned_dev_count = scan_response_count;
	uint8_t perception_supp_scan_index[MAX_SCAN_DEVICE];
	uint8_t scan_index = 0;
	uint8_t index;
	at_ble_scan_info_t *scan_buffer = (at_ble_scan_info_t *)scan_info;
	memset(scan_device, 0, MAX_SCAN_DEVICE);
	if (scanned_dev_count) {
		
		at_ble_uuid_t service_uuid;

		for (index = 0; index < scanned_dev_count; index++) {			
			/* Display only the connectible devices*/
			if((scan_buffer[index].type == AT_BLE_ADV_TYPE_DIRECTED) 
				|| (scan_buffer[index].type == AT_BLE_ADV_TYPE_UNDIRECTED)) {				
				scan_device[perception_scan_device_count++] = index;
			}
		}
		
		if (perception_scan_device_count) {		
			/* Service type to be searched */
			service_uuid.type = AT_BLE_UUID_16;

			/* Service UUID */
			service_uuid.uuid[1] = (uint8_t)(PERCEPTION_SERVICE_UUID >> 8);
			service_uuid.uuid[0] = (uint8_t)(PERCEPTION_SERVICE_UUID >> 0);
			
			for (index = 0; index < perception_scan_device_count; index++) {
				DBG_LOG("Info: Device found address [%d]  0x%02X%02X%02X%02X%02X%02X ",
				index,
				scan_buffer[scan_device[index]].dev_addr.addr[5],
				scan_buffer[scan_device[index]].dev_addr.addr[4],
				scan_buffer[scan_device[index]].dev_addr.addr[3],
				scan_buffer[scan_device[index]].dev_addr.addr[2],
				scan_buffer[scan_device[index]].dev_addr.addr[1],
				scan_buffer[scan_device[index]].dev_addr.addr[0]);
				
				if (scan_info_parse(&scan_buffer[scan_device[index]], &service_uuid,
				AD_TYPE_COMPLETE_LIST_UUID) ==
				AT_BLE_SUCCESS) {
					/* Device Service UUID  matched */
					perception_supp_scan_index[scan_index++] = index;
					DBG_LOG_CONT("---Perception");
				}
			}			
		}

		if (!scan_index)  {
			DBG_LOG("Perception supported device not found ");
		}		
		
		/* Stop the current scan active */
		at_ble_scan_stop();
		
		/*Updating the index pointer to connect */
		//if(perception_scan_device_count) {  
			/* Successful device found event*/
			/*uint8_t deci_index = perception_scan_device_count;
			deci_index+=PERCEPTION_ASCII_TO_DECIMAL_VALUE;
			do {
				DBG_LOG("Select Index number to Connect or [s] to scan");
				index = getchar_b11();
				DBG_LOG("%c", index);
			} while (!(((index < (deci_index)) && (index >='0')) || (index == 's')));	
			
			if(index == 's') {
				return gap_dev_scan();
			} else {
				index -= PERCEPTION_ASCII_TO_DECIMAL_VALUE;
				return perception_connect_request(scan_buffer,scan_device[index]);
			}			
		}*/
		if (scan_index) {
			return perception_connect_request(scan_buffer, scan_device[perception_supp_scan_index[scan_index-1]]);
		}
	}
		/* from no device found event*/
		/*do
		{
			DBG_LOG("Select [s] to scan again");
			index = getchar_b11();
			DBG_LOG("%c", index);
		} while (!(index == 's')); 
		
		if(index == 's') {
			return gap_dev_scan();
		}*/	
		
    ALL_UNUSED(param);
	return gap_dev_scan();
}

/* Callback registered for AT_BLE_CONNECTED event from stack */
static at_ble_status_t ble_connected_app_event(void *param)
{
	at_ble_connected_t *conn_params;
	conn_params = (at_ble_connected_t *)param;	
	
	if(!ble_check_iscentral(conn_params->handle))
	{
		return AT_BLE_FAILURE;
	}

	perception_state_flag = PERCEPTION_DEV_CONNECTED;

	at_ble_status_t discovery_status = AT_BLE_FAILURE;
	discovery_status = perception_service_discover(conn_params->handle);

	return discovery_status;
}

/* Callback registered for AT_BLE_DISCONNECTED event from stack */
static at_ble_status_t ble_disconnected_app_event(void *param)
{
	at_ble_disconnected_t *disconnect;
	disconnect = (at_ble_disconnected_t *)param;
	
	if((ble_check_device_state(disconnect->handle, BLE_DEVICE_DISCONNECTED) == AT_BLE_SUCCESS) ||
	(ble_check_device_state(disconnect->handle, BLE_DEVICE_DEFAULT_IDLE) == AT_BLE_SUCCESS)) {
		if (disconnect->reason == AT_BLE_LL_COMMAND_DISALLOWED) {
			return AT_BLE_SUCCESS;
		} else {
			perception_start_scan();
		}
	}

	return AT_BLE_FAILURE;
}

/* Callback registered for AT_BLE_PAIR_DONE event from stack */
static at_ble_status_t ble_paired_app_event(void *param)
{
	ALL_UNUSED(param);
	DBG_LOG("PAIRED??? OK THEN");
	return AT_BLE_SUCCESS;
}

/* Callback registered for AT_BLE_PRIMARY_SERVICE_FOUND event from stack */
static at_ble_status_t ble_service_found_app_event(void *param)
{
	at_ble_uuid_t *perception_service_uuid;
	at_ble_status_t status = AT_BLE_SUCCESS;
	at_ble_primary_service_found_t *primary_service_params;
	primary_service_params = (at_ble_primary_service_found_t *)param;
	
	if(!ble_check_iscentral(primary_service_params->conn_handle))
	{
		return AT_BLE_FAILURE;
	}
	
	perception_state_flag = PERCEPTION_DEV_SERVICE_FOUND;
	
	perception_service_uuid = &primary_service_params->service_uuid;
	if (perception_service_uuid->type == AT_BLE_UUID_16) {
		uint16_t service_uuid;
		service_uuid= ((perception_service_uuid->uuid[1] << 8)
					  | perception_service_uuid->uuid[0]);
		switch (service_uuid) {
			// Perception Vibe Motor Service UUID
			case PERCEPTION_SERVICE_UUID:
			{
				perception_handle.start_handle = primary_service_params->start_handle;
				perception_handle.end_handle = primary_service_params->end_handle;
				DBG_LOG("Perception service discovered");
				DBG_LOG_PTS("start_handle: %04X end_handle: %04X",
				primary_service_params->start_handle,
				primary_service_params->end_handle);
				perception_handle.char_discovery=(at_ble_status_t)DISCOVER_SUCCESS;
			}
			break;

			default:
				status = AT_BLE_INVALID_PARAM;
				break;
		}
	}
	return status;
}

/* Callback registered for AT_BLE_CHARACTERISTIC_FOUND event from stack */
static at_ble_status_t ble_char_found_app_event(void *param)
{
	uint16_t charac_16_uuid;
	at_ble_characteristic_found_t *characteristic_found;
	characteristic_found = (at_ble_characteristic_found_t *)param;
	
	if(!ble_check_iscentral(characteristic_found->conn_handle))
	{
		return AT_BLE_FAILURE;
	}

	charac_16_uuid = (uint16_t)((characteristic_found->char_uuid.uuid[0]) |	\
	(characteristic_found->char_uuid.uuid[1] << 8));

	if (charac_16_uuid == VIBE1_INTENSITY_CHAR_UUID) {
		perception_handle.char_handle1 = characteristic_found->value_handle;
		vibe1_char_found = true;
		DBG_LOG_PTS("Vibe 1 intensity characteristics: Attrib handle %x property %x handle: %x uuid : %x",
		characteristic_found->char_handle, characteristic_found->properties,
		perception_handle.char_handle1, charac_16_uuid);
	} else if (charac_16_uuid == VIBE2_INTENSITY_CHAR_UUID) {
		perception_handle.char_handle2 = characteristic_found->value_handle;
		vibe2_char_found = true;
		DBG_LOG_PTS("Vibe 2 intensity characteristics: Attrib handle %x property %x handle: %x uuid : %x",
		characteristic_found->char_handle, characteristic_found->properties,
		perception_handle.char_handle2, charac_16_uuid);
	} else if (charac_16_uuid == VIBE3_INTENSITY_CHAR_UUID) {
		perception_handle.char_handle3 = characteristic_found->value_handle;
		vibe3_char_found = true;
		DBG_LOG_PTS("Vibe 3 intensity characteristics: Attrib handle %x property %x handle: %x uuid : %x",
		characteristic_found->char_handle, characteristic_found->properties,
		perception_handle.char_handle3, charac_16_uuid);
	} else if (charac_16_uuid == VIBE4_INTENSITY_CHAR_UUID) {
		perception_handle.char_handle4 = characteristic_found->value_handle;
		vibe4_char_found = true;
		DBG_LOG_PTS("Vibe 4 intensity characteristics: Attrib handle %x property %x handle: %x uuid : %x",
		characteristic_found->char_handle, characteristic_found->properties,
		perception_handle.char_handle4, charac_16_uuid);
	}
	return AT_BLE_SUCCESS;
}

/* Callback registered for AT_BLE_DISCOVERY_COMPLETE event from stack */
static at_ble_status_t ble_discovery_complete_app_event(void *param)
{
	bool discover_char_flag = true;
	at_ble_discovery_complete_t *discover_status;
	discover_status = (at_ble_discovery_complete_t *)param;
	
	if(!ble_check_iscentral(discover_status->conn_handle))
	{
		return AT_BLE_FAILURE;
	}
	
	DBG_LOG_DEV("discover complete operation %d and %d",discover_status->operation,discover_status->status);
	if ((discover_status->status == DISCOVER_SUCCESS) || (discover_status->status == AT_BLE_SUCCESS)) {
		at_ble_status_t status;
		if ((perception_handle.char_discovery == DISCOVER_SUCCESS) && (discover_char_flag)) {
			if ((status = at_ble_characteristic_discover_all(
				discover_status->conn_handle,
				perception_handle.start_handle,
				perception_handle.end_handle)) ==
			AT_BLE_SUCCESS) {
				DBG_LOG_DEV("Perception Characteristic Discovery Started");
			} else {
				DBG_LOG("Perception Characteristic Discovery Failed: %02x", status);
			}
			perception_handle.char_discovery = AT_BLE_FAILURE;
			discover_char_flag = false;
		} else if (perception_handle.char_discovery == AT_BLE_INVALID_PARAM) {
			DBG_LOG("Perception Service Not Found");
			perception_handle.char_discovery = AT_BLE_INVALID_STATE;
			discover_char_flag = false;
		}
		
		if (perception_handle.char_discovery == AT_BLE_INVALID_STATE) {
			DBG_LOG("PERCEPTION PROFILE NOT SUPPORTED");
			discover_char_flag = false;
			at_ble_disconnect(discover_status->conn_handle, AT_BLE_TERMINATED_BY_USER);
		}
		
		
		if (discover_char_flag) {
			DBG_LOG_DEV("GATT characteristic discovery completed");
			if (vibe1_char_found && vibe2_char_found && vibe3_char_found && vibe4_char_found) {
				perception_state_flag = PERCEPTION_DEV_CHAR_ALL_VIBE_FOUND;
				hw_timer_start(PERCEPTION_CHAR_READ_INTERVAL);
			}
		}
	}
	return AT_BLE_SUCCESS;
}

/* Callback registered for AT_BLE_CHARACTERISTIC_READ_RESPONSE event from stack */
static at_ble_status_t ble_char_read_resp_app_event(void *param)
{
	at_ble_characteristic_read_response_t *char_read_resp;
	char_read_resp = (at_ble_characteristic_read_response_t *)param;
	
	if(!ble_check_iscentral(char_read_resp->conn_handle))
	{
		return AT_BLE_FAILURE;
	}

	DBG_LOG_DEV("Read Resp handle %x",
		char_read_resp->char_handle);
	
	if (char_read_resp->char_handle == perception_handle.char_handle1) {
		DBG_LOG("Vibe 1\n");
		memcpy(&perception_handle.char_data1[0],
			   &char_read_resp->char_value[PERCEPTION_READ_OFFSET],
			   PERCEPTION_READ_LENGTH);
		for (int i = 0; i < PERCEPTION_READ_LENGTH; i++) {
			DBG_LOG_CONT("%d", perception_handle.char_data1[i]);
		}
		DBG_LOG(" ");
		vibe1_duty = perception_handle.char_data1[0] * 10;
		pwm_set_duty_cycle(VIBE1, vibe1_duty);
	} else if (char_read_resp->char_handle == perception_handle.char_handle2) {
		DBG_LOG("Vibe 2\n");
		memcpy(perception_handle.char_data2,
			   &char_read_resp->char_value[PERCEPTION_READ_OFFSET],
			   PERCEPTION_READ_LENGTH);
		for (int i = 0; i < PERCEPTION_READ_LENGTH; i++) {
			DBG_LOG_CONT("%d", perception_handle.char_data2[i]);
		}
		DBG_LOG(" ");
		vibe2_duty = perception_handle.char_data2[0] * 10;
		pwm_set_duty_cycle(VIBE2, vibe2_duty);
	} else if (char_read_resp->char_handle == perception_handle.char_handle3) {
		DBG_LOG("Vibe 3\n");
		memcpy(perception_handle.char_data3,
			   &char_read_resp->char_value[PERCEPTION_READ_OFFSET],
			   PERCEPTION_READ_LENGTH);
		for (int i = 0; i < PERCEPTION_READ_LENGTH; i++) {
			DBG_LOG_CONT("%d", perception_handle.char_data3[i]);
		}
		DBG_LOG(" ");
		vibe3_duty = perception_handle.char_data3[0] * 10;
		pwm_set_duty_cycle(VIBE3, vibe3_duty);
	} else if (char_read_resp->char_handle == perception_handle.char_handle4) {
		DBG_LOG("Vibe 4\n");
		memcpy(perception_handle.char_data4,
			   &char_read_resp->char_value[PERCEPTION_READ_OFFSET],
			   PERCEPTION_READ_LENGTH);
		for (int i = 0; i < PERCEPTION_READ_LENGTH; i++) {
			DBG_LOG_CONT("%d", char_read_resp->char_value[i]/*perception_handle.char_data4[i]*/);
		}
		DBG_LOG(" ");
		vibe4_duty = perception_handle.char_data4[0] * 10;
		pwm_set_duty_cycle(VIBE4, vibe4_duty);
	} else if (char_read_resp->char_handle == 0xf208) {
		perception_state_flag = PERCEPTION_DEV_UNCONNECTED;
		if (AT_BLE_SUCCESS == at_ble_disconnect(char_read_resp->conn_handle, AT_BLE_TERMINATED_BY_USER)) {
			DBG_LOG("Connection Lost");
		}
	}
	return AT_BLE_SUCCESS;
}

static const ble_event_callback_t perception_gap_cb[] = {
	NULL,
	NULL,
	ble_scan_report_app_event,
	NULL,
	NULL,
	ble_connected_app_event,
	ble_disconnected_app_event,
	NULL,
	NULL,
	ble_paired_app_event,
	NULL,
	NULL,
	NULL,
	NULL,
	ble_paired_app_event,
	NULL,
	NULL,
	NULL,
	NULL
};

static const ble_event_callback_t perception_gatt_client_cb[] = {
	ble_service_found_app_event,
	NULL,
	ble_char_found_app_event,
	NULL,
	ble_discovery_complete_app_event,
	ble_char_read_resp_app_event,
	NULL,
	NULL,
	NULL,
	NULL
};

/* timer callback function */
static void timer_callback_fn(void)
{
	// Stop the timer
	hw_timer_stop();

	// Enable flag to serve app task
	timer_done = true;

	send_plf_int_msg_ind(USER_TIMER_CALLBACK, TIMER_EXPIRED_CALLBACK_TYPE_DETECT, NULL, 0);
}

int main(void)
{
	platform_driver_init();
	acquire_sleep_lock();

	// Initialize serial console
	serial_console_init();
	
	// Hardware timer
	hw_timer_init();
	
	hw_timer_register_callback(timer_callback_fn);

	configure_pwm();

	DBG_LOG("Initializing Perception Application");
	
	// Initialize the BLE chip and Set the Device Address
	ble_device_init(NULL);

	// Initialize Perception Characteristic Handler
	perception_handle.char_data1 = perception_char_data1;
	perception_handle.char_data2 = perception_char_data2;
	perception_handle.char_data3 = perception_char_data3;
	perception_handle.char_data4 = perception_char_data4;
	
	// Register callbacks for gap related events
	ble_mgr_events_callback_handler(REGISTER_CALL_BACK,
									BLE_GAP_EVENT_TYPE,
									perception_gap_cb);
	
	// Register callbacks for gatt client related events
	ble_mgr_events_callback_handler(REGISTER_CALL_BACK,
									BLE_GATT_CLIENT_EVENT_TYPE,
									perception_gatt_client_cb);

	perception_app_init();
	
	while(true)
	{
		// BLE Event task
		ble_event_task(BLE_EVENT_TIMEOUT);
		
		// Application task
		if (timer_done) {
			if (perception_state_flag == PERCEPTION_DEV_CONNECTING) {
				at_ble_disconnected_t perception_connect_request_fail;
				perception_connect_request_fail.reason = AT_BLE_TERMINATED_BY_USER;
				perception_connect_request_fail.handle = ble_dev_info[0].conn_info.handle;
				perception_state_flag = PERCEPTION_DEV_UNCONNECTED;
				if (at_ble_connect_cancel() == AT_BLE_SUCCESS) {
					DBG_LOG("Connection Timeout");
					ble_disconnected_app_event(&perception_connect_request_fail);
				} else {
					DBG_LOG("Unable to connect with device");
				}
			}

			if (perception_state_flag == PERCEPTION_DEV_CHAR_ALL_VIBE_FOUND) {
				if (!(at_ble_characteristic_read(ble_dev_info[0].conn_info.handle,
												 perception_handle.char_handle1,
												 PERCEPTION_READ_OFFSET,
												 PERCEPTION_READ_LENGTH)
												 == AT_BLE_SUCCESS)) {
					DBG_LOG("Vibe Motor 1 Characteristic Read Request Failed");
				}
				if (!(at_ble_characteristic_read(ble_dev_info[0].conn_info.handle,
												 perception_handle.char_handle2,
												 PERCEPTION_READ_OFFSET,
												 PERCEPTION_READ_LENGTH)
												 == AT_BLE_SUCCESS)) {
					DBG_LOG("Vibe Motor 2 Characteristic Read Request Failed");
				}
				if (!(at_ble_characteristic_read(ble_dev_info[0].conn_info.handle,
												 perception_handle.char_handle3,
												 PERCEPTION_READ_OFFSET,
												 PERCEPTION_READ_LENGTH)
												 == AT_BLE_SUCCESS)) {
					DBG_LOG("Vibe Motor 3 Characteristic Read Request Failed");
				}
				if (!(at_ble_characteristic_read(ble_dev_info[0].conn_info.handle,
												 perception_handle.char_handle4,
												 PERCEPTION_READ_OFFSET,
												 PERCEPTION_READ_LENGTH)
												 == AT_BLE_SUCCESS)) {
					DBG_LOG("Vibe Motor 4 Characteristic Read Request Failed");
				}

				hw_timer_start(PERCEPTION_CHAR_READ_INTERVAL);
			}

			timer_done = false;
		}
	}

}

