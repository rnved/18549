/**
* \file
*
* \brief Proximity Monitor Profile
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
* This is the reference manual for the Proximity Monitor Profile
*/
/*- Includes ---------------------------------------------------------------*/
#include <asf.h>
#include "platform.h"
#include "pxp_monitor.h"
#include "console_serial.h"


static const ble_event_callback_t pxp_gap_handle[] = {
	NULL,
	NULL,
	pxp_monitor_scan_data_handler,
	NULL,
	NULL,
	pxp_monitor_connected_state_handler,
	pxp_disconnect_event_handler,
	NULL,
	NULL,
	pxp_monitor_pair_done_handler,
	NULL,
	NULL,
	NULL,
	NULL,
	pxp_monitor_encryption_change_handler,
	NULL,
	NULL,
	NULL,
	NULL
};

static const ble_event_callback_t pxp_gatt_client_handle[] = {
	pxp_monitor_service_found_handler,
	NULL,
	pxp_monitor_characteristic_found_handler,
	NULL,
	pxp_monitor_discovery_complete_handler,
	pxp_monitor_characteristic_read_response,
	NULL,
	NULL,
	NULL,
	NULL
};

extern ble_connected_dev_info_t *ble_dev_info;

/* pxp reporter device address to connect */
at_ble_addr_t pxp_reporter_address;

uint8_t pxp_supp_scan_index[MAX_SCAN_DEVICE];
uint8_t scan_index = 0;


extern volatile uint8_t scan_response_count;
extern at_ble_scan_info_t scan_info[MAX_SCAN_DEVICE];

volatile uint8_t pxp_connect_request_flag = PXP_DEV_UNCONNECTED;

gatt_perception_char_handler_t perception_handle =
{0, 0, 0, 0, 0, 0, AT_BLE_INVALID_PARAM, NULL, NULL, NULL, NULL};
uint8_t perception_char_data1[MAX_PERCEPTION_CHAR_SIZE];
uint8_t perception_char_data2[MAX_PERCEPTION_CHAR_SIZE];
uint8_t perception_char_data3[MAX_PERCEPTION_CHAR_SIZE];
uint8_t perception_char_data4[MAX_PERCEPTION_CHAR_SIZE];


hw_timer_start_func_cb_t hw_timer_start_func_cb = NULL;
hw_timer_stop_func_cb_t hw_timer_stop_func_cb = NULL;
peripheral_state_cb_t peripheral_state_callback = NULL;

/* *@brief Initializes Proximity profile
* handler Pointer reference to respective variables
*
*/
void pxp_monitor_init(void *param)
{
	UNUSED(param);
	
	perception_handle.char_data1 = perception_char_data1;
	perception_handle.char_data2 = perception_char_data2;
	perception_handle.char_data3 = perception_char_data3;
	perception_handle.char_data4 = perception_char_data4;
	
	ble_mgr_events_callback_handler(REGISTER_CALL_BACK, BLE_GAP_EVENT_TYPE, pxp_gap_handle);
	ble_mgr_events_callback_handler(REGISTER_CALL_BACK, BLE_GATT_CLIENT_EVENT_TYPE, pxp_gatt_client_handle);
}

/**@brief Connect to a peer device
*
* Connecting to a peer device, implicitly starting the necessary scan operation
* then connecting if a device in the peers list is found.
*
* @param[in] scan_buffer a list of peers that the device will connect to one of
* them
* @param[in] index index of elements in peers, to initiate the connection
*
* @return @ref AT_BLE_SUCCESS operation programmed successfully
* @return @ref AT_BLE_INVALID_PARAM incorrect parameter.
* @return @ref AT_BLE_FAILURE Generic error.
*/
at_ble_status_t pxp_monitor_connect_request(at_ble_scan_info_t *scan_buffer,
uint8_t index)
{
	memcpy((uint8_t *)&pxp_reporter_address,
	(uint8_t *)&scan_buffer[index].dev_addr,
	sizeof(at_ble_addr_t));

	if (gap_dev_connect(&pxp_reporter_address) == AT_BLE_SUCCESS) {
		DBG_LOG("Perception Connect request sent");
		pxp_connect_request_flag = PXP_DEV_CONNECTING;
		hw_timer_start_func_cb(PXP_CONNECT_REQ_INTERVAL);
		return AT_BLE_SUCCESS;
		} else {
		DBG_LOG("Perception Connect request send failed");
	}

	return AT_BLE_FAILURE;
}

/**@brief Search for a given AD type in a buffer, received from advertising
* packets starts search from the buffer, need to provide required
* search params
*
* @param[in] scan_buffer where all received advertising packet are stored
* @param[in] scanned_dev_count elements in scan_buffer
*
* @return @ref AT_BLE_SUCCESS operation programmed successfully
* @return @ref AT_BLE_INVALID_PARAM incorrect parameter.
* @return @ref AT_BLE_FAILURE Generic error.
*/
at_ble_status_t pxp_monitor_scan_data_handler(void *params)
{
	uint8_t scan_device[MAX_SCAN_DEVICE];
	uint8_t pxp_scan_device_count = 0;
	uint8_t scanned_dev_count = scan_response_count;
	scan_index = 0;
	uint8_t index;
	at_ble_scan_info_t *scan_buffer = (at_ble_scan_info_t *)scan_info;
	memset(scan_device, 0, MAX_SCAN_DEVICE);
	if (scanned_dev_count) {
		
		at_ble_uuid_t service_uuid;

		for (index = 0; index < scanned_dev_count; index++) {			
			/* Display only the connectible devices*/
			if((scan_buffer[index].type == AT_BLE_ADV_TYPE_DIRECTED) 
				|| (scan_buffer[index].type == AT_BLE_ADV_TYPE_UNDIRECTED)) {				
				scan_device[pxp_scan_device_count++] = index;
			}
		}
		
		if (pxp_scan_device_count) {		
			/* Service type to be searched */
			service_uuid.type = AT_BLE_UUID_16;

			/* Service UUID */
			/*service_uuid.uuid[15] = (uint8_t)(0x63146596 >> 24);
			service_uuid.uuid[14] = (uint8_t)(0x63146596 >> 16);
			service_uuid.uuid[13] = (uint8_t)(0x63146596 >> 8);
			service_uuid.uuid[12] = (uint8_t)(0x63146596 >> 0);
			service_uuid.uuid[11] = (uint8_t)(0x6BB64229 >> 24);
			service_uuid.uuid[10] = (uint8_t)(0x6BB64229 >> 16);
			service_uuid.uuid[9] = (uint8_t)(0x6BB64229 >> 8);
			service_uuid.uuid[8] = (uint8_t)(0x6BB64229 >> 0);
			service_uuid.uuid[7] = (uint8_t)(0x9928C2F8 >> 24);
			service_uuid.uuid[6] = (uint8_t)(0x9928C2F8 >> 16);
			service_uuid.uuid[5] = (uint8_t)(0x9928C2F8 >> 8);
			service_uuid.uuid[4] = (uint8_t)(0x9928C2F8 >> 0);
			service_uuid.uuid[3] = (uint8_t)(0xC3B20C01 >> 24);
			service_uuid.uuid[2] = (uint8_t)(0xC3B20C01 >> 16);
			service_uuid.uuid[1] = (uint8_t)(0xC3B20C01 >> 8);//(LINK_LOSS_SERVICE_UUID >> 8);
			service_uuid.uuid[0] = (uint8_t)(0xC3B20C01 >> 0);//(uint8_t)LINK_LOSS_SERVICE_UUID;
			*/
			service_uuid.uuid[1] = (uint8_t)(PERCEPTION_SERVICE_UUID >> 8);
			service_uuid.uuid[0] = (uint8_t)(PERCEPTION_SERVICE_UUID >> 0);
			//service_uuid.uuid[1] = (LINK_LOSS_SERVICE_UUID >> 8);
			//service_uuid.uuid[0] = (uint8_t)LINK_LOSS_SERVICE_UUID;
			
			for (index = 0; index < pxp_scan_device_count; index++) {
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
					pxp_supp_scan_index[scan_index++] = index;
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
		if(pxp_scan_device_count) {  
			/* Successful device found event*/
			uint8_t deci_index = pxp_scan_device_count;
			deci_index+=PXP_ASCII_TO_DECIMAL_VALUE;
			do {
				DBG_LOG("Select Index number to Connect or [s] to scan");
				index = getchar_b11();
				DBG_LOG("%c", index);
			} while (!(((index < (deci_index)) && (index >='0')) || (index == 's')));	
			
			if(index == 's') {
				return gap_dev_scan();
			} else {
				index -= PXP_ASCII_TO_DECIMAL_VALUE;
				return pxp_monitor_connect_request(scan_buffer,	scan_device[index]);
			}			
		}			
	} else {  
		/* from no device found event*/
		do
		{
			DBG_LOG("Select [s] to scan again");
			index = getchar_b11();
			DBG_LOG("%c", index);
		} while (!(index == 's')); 
		
		if(index == 's') {
			return gap_dev_scan();
		}
	}		
        ALL_UNUSED(params);
	return AT_BLE_FAILURE;
}

at_ble_status_t pxp_monitor_start_scan(void)
{
	if (peripheral_state_callback != NULL)
	{
		if (peripheral_state_callback() == PERIPHERAL_ADVERTISING_STATE)
		{
			DBG_LOG("Peripheral is already Advertising. Scan not permitted");
			return AT_BLE_FAILURE;
		}
	}
	
	char index_value;
	hw_timer_stop_func_cb();
	do
	{
		DBG_LOG("Select [r] to Reconnect or [s] Scan");
		index_value = getchar_b11();
		DBG_LOG("%c", index_value);
	}	while (!((index_value == 'r') || (index_value == 's')));
	
	if(index_value == 'r') {
		if (gap_dev_connect(&pxp_reporter_address) == AT_BLE_SUCCESS) {
			DBG_LOG("Perception Re-Connect request sent");
			pxp_connect_request_flag = PXP_DEV_CONNECTING;
			hw_timer_start_func_cb(PXP_CONNECT_REQ_INTERVAL);
			return AT_BLE_SUCCESS;
			} else {
			DBG_LOG("Perception Re-Connect request send failed");
		}
	}
	else if(index_value == 's') {
		return gap_dev_scan();
	}
	return AT_BLE_FAILURE;
}

/**@brief peer device connection terminated
*
* handler for disconnect notification
* try to send connect request for previously connect device.
*
* @param[in] available disconnect handler of peer and
* reason for disconnection
*
* @return @ref AT_BLE_SUCCESS Reconnect request sent to previously connected
*device
* @return @ref AT_BLE_FAILURE Reconnection fails.
*/
at_ble_status_t pxp_disconnect_event_handler(void *params)
{	
	at_ble_disconnected_t *disconnect;
	disconnect = (at_ble_disconnected_t *)params;
	static ble_peripheral_state_t peripheral_state = PERIPHERAL_IDLE_STATE;
	
	if(!ble_check_disconnected_iscentral(disconnect->handle))
	{
		pxp_monitor_start_scan();
		return AT_BLE_FAILURE;
	}
	else if(peripheral_state_callback != NULL)
	{
		peripheral_state = peripheral_state_callback();
	}
	
	if(peripheral_state != PERIPHERAL_ADVERTISING_STATE)
	{
		if((ble_check_device_state(disconnect->handle, BLE_DEVICE_DISCONNECTED) == AT_BLE_SUCCESS) ||
		(ble_check_device_state(disconnect->handle, BLE_DEVICE_DEFAULT_IDLE) == AT_BLE_SUCCESS))
		{
			if (disconnect->reason == AT_BLE_LL_COMMAND_DISALLOWED) {
				return AT_BLE_SUCCESS;
			} else
				pxp_monitor_start_scan();
		}
	}
	else
	{
		pxp_connect_request_flag = PXP_DEV_UNCONNECTED;
		DBG_LOG("Peripheral is already Advertising,Scan not permitted");
	}

	return AT_BLE_FAILURE;
}

/**@brief Discover all services
 *
 * @param[in] connection handle.
 * @return @ref AT_BLE_SUCCESS operation programmed successfully.
 * @return @ref AT_BLE_INVALID_PARAM incorrect parameter.
 * @return @ref AT_BLE_FAILURE Generic error.
 */
at_ble_status_t pxp_monitor_service_discover(at_ble_handle_t handle)
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

at_ble_status_t pxp_monitor_pair_done_handler(void *params)
{
	DBG_LOG("PAIR DONE HANDLER");
	at_ble_status_t discovery_status = AT_BLE_FAILURE;
	at_ble_pair_done_t *pair_done_val;
	pair_done_val = (at_ble_pair_done_t *)params;		
		
	if(!ble_check_iscentral(pair_done_val->handle))
	{
		return AT_BLE_FAILURE;
	}
	
	hw_timer_stop_func_cb();
	
	if (pair_done_val->status == AT_BLE_SUCCESS) {
		discovery_status = pxp_monitor_service_discover(pair_done_val->handle);
	} else {
		DBG_LOG("FAILURE");
		return AT_BLE_FAILURE;
	}
	
	pxp_connect_request_flag = PXP_DEV_PAIRED;
	
	return discovery_status;
}

at_ble_status_t pxp_monitor_encryption_change_handler(void *params)
{
	at_ble_status_t discovery_status = AT_BLE_FAILURE;
	at_ble_encryption_status_changed_t *encryption_status;
	encryption_status = (at_ble_encryption_status_changed_t *)params;
	
	if(!ble_check_iscentral(encryption_status->handle))
	{
		return AT_BLE_FAILURE;
	}
	hw_timer_stop_func_cb();
	if (encryption_status->status == AT_BLE_SUCCESS) {
		discovery_status = pxp_monitor_service_discover(encryption_status->handle);
	}
	return discovery_status;
}

/**@brief Connected event state handle after connection request to peer device
*
* After connecting to the peer device start the GATT primary discovery
*
* @param[in] conn_params parameters of the established connection
*
* @return @ref AT_BLE_SUCCESS operation successfully.
* @return @ref AT_BLE_INVALID_PARAM if GATT discovery parameter are incorrect
*parameter.
* @return @ref AT_BLE_FAILURE Generic error.
*/
at_ble_status_t pxp_monitor_connected_state_handler(void *params)
{
	at_ble_connected_t *conn_params;
	conn_params = (at_ble_connected_t *)params;	
	
	if(!ble_check_iscentral(conn_params->handle))
	{
		return AT_BLE_FAILURE;
	}

	pxp_connect_request_flag = PXP_DEV_CONNECTED;

	at_ble_status_t discovery_status = AT_BLE_FAILURE;
	discovery_status = pxp_monitor_service_discover(conn_params->handle);
	
	/*at_ble_pair_features_t features;
	features.bond = false;
	features.desired_auth = AT_BLE_NO_SEC;
	features.initiator_keys = AT_BLE_KEY_DIST_NONE;
	features.io_cababilities = AT_BLE_IO_CAP_NO_INPUT_NO_OUTPUT;
	features.max_key_size = AT_BLE_MAX_KEY_LEN;
	features.min_key_size = 8;
	features.mitm_protection = false;
	features.oob_avaiable = false;
	features.responder_keys = AT_BLE_KEY_DIST_NONE;
	
	uint8_t idx;
	for (idx = 0; idx < BLE_MAX_DEVICE_CONNECTED; idx++)
	{
		if((ble_dev_info[idx].conn_info.handle == conn_params->handle) && (ble_dev_info[idx].conn_state == BLE_DEVICE_CONNECTED))
		{
			ble_dev_info[idx].conn_state = BLE_DEVICE_PAIRING;
			break;
		}
	}
	
	at_ble_status_t status = at_ble_authenticate(conn_params->handle, &features, NULL, NULL);
	if (AT_BLE_SUCCESS != status) {
		DBG_LOG("Pairing Failed, Status: 0x%x", status);
	}*/
		
	return discovery_status;
	//return conn_params->conn_status;
}

/**@brief Discover the Proximity services
*
* Search will go from start_handle to end_handle, whenever a service is found
*and
* compare with proximity services and stores the respective handlers
* @ref PXP_MONITOR_CONNECTED_STATE_HANDLER event i.
*
* @param[in] at_ble_primary_service_found_t  Primary service parameter
*
*/
at_ble_status_t pxp_monitor_service_found_handler(void *params)
{
	at_ble_uuid_t *pxp_service_uuid;
	at_ble_status_t status = AT_BLE_SUCCESS;
	at_ble_primary_service_found_t *primary_service_params;
	primary_service_params = (at_ble_primary_service_found_t *)params;
	
	if(!ble_check_iscentral(primary_service_params->conn_handle))
	{
		return AT_BLE_FAILURE;
	}
	
	pxp_connect_request_flag = PXP_DEV_SERVICE_FOUND;
	
	pxp_service_uuid = &primary_service_params->service_uuid;
	if (pxp_service_uuid->type == AT_BLE_UUID_16) {
		uint16_t service_uuid;
		service_uuid
		= ((pxp_service_uuid->uuid[1] <<
		8) | pxp_service_uuid->uuid[0]);
		switch (service_uuid) {
			// Perception Vibe Motor Service UUID
			case PERCEPTION_SERVICE_UUID:
			{
				perception_handle.start_handle
				= primary_service_params->start_handle;
				perception_handle.end_handle
				= primary_service_params->end_handle;
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

/**@brief Discover all Characteristics supported for Proximity Service of a
* connected device
*  and handles discovery complete
* Search will go from start_handle to end_handle, whenever a characteristic is
*found
* After search and discovery completes will initialize the alert level and read
*the tx power value as defined
* @ref AT_BLE_CHARACTERISTIC_FOUND event is sent and @ref
*AT_BLE_DISCOVERY_COMPLETE is sent at end of discover operation.
*
* @param[in] discover_status discovery status of each handle
*
*/
at_ble_status_t pxp_monitor_discovery_complete_handler(void *params)
{
	bool discover_char_flag = true;
	at_ble_discovery_complete_t *discover_status;
	discover_status = (at_ble_discovery_complete_t *)params;
	
	if(!ble_check_iscentral(discover_status->conn_handle))
	{
		return AT_BLE_FAILURE;
	}
	
	DBG_LOG_DEV("discover complete operation %d and %d",discover_status->operation,discover_status->status);
	if ((discover_status->status == DISCOVER_SUCCESS) || (discover_status->status == AT_BLE_SUCCESS)) {
		at_ble_status_t status;
		if ((perception_handle.char_discovery == DISCOVER_SUCCESS) && (discover_char_flag)) {
			/*at_ble_uuid_t c_uuid;
			c_uuid.type = AT_BLE_UUID_16;
			c_uuid.uuid[1] = (uint8_t)(VIBE1_INTENSITY_CHAR_UUID >> 8);
			c_uuid.uuid[0] = (uint8_t)(VIBE1_INTENSITY_CHAR_UUID);*/
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
	
			if (!(at_ble_characteristic_read(discover_status->conn_handle,
			perception_handle.char_handle1,
			PERCEPTION_READ_OFFSET,
			PERCEPTION_READ_LENGTH) == AT_BLE_SUCCESS)) {
				DBG_LOG("Vibe Motor 1 Characteristic Read Request Failed");
			}
			if (!(at_ble_characteristic_read(discover_status->conn_handle,
			perception_handle.char_handle2,
			PERCEPTION_READ_OFFSET,
			PERCEPTION_READ_LENGTH) == AT_BLE_SUCCESS)) {
				DBG_LOG("Vibe Motor 2 Characteristic Read Request Failed");
			}
			if (!(at_ble_characteristic_read(discover_status->conn_handle,
			perception_handle.char_handle3,
			PERCEPTION_READ_OFFSET,
			PERCEPTION_READ_LENGTH) == AT_BLE_SUCCESS)) {
				DBG_LOG("Vibe Motor 3 Characteristic Read Request Failed");
			}
			if (!(at_ble_characteristic_read(discover_status->conn_handle,
			perception_handle.char_handle4,
			PERCEPTION_READ_OFFSET,
			PERCEPTION_READ_LENGTH) == AT_BLE_SUCCESS)) {
				DBG_LOG("Vibe Motor 4 Characteristic Read Request Failed");
			}
		}
	}
	return AT_BLE_SUCCESS;
}

/**@brief Handles the read response from the peer/connected device
*
* if any read request send, response back event is handle.
* compare the read response characteristics with available service.
* and data is handle to the respective service.
*/
at_ble_status_t pxp_monitor_characteristic_read_response(void *params)
{
	at_ble_characteristic_read_response_t *char_read_resp;
	char_read_resp = (at_ble_characteristic_read_response_t *)params;
	
	if(!ble_check_iscentral(char_read_resp->conn_handle))
	{
		return AT_BLE_FAILURE;
	}

	DBG_LOG("Read Resp handle %x",
	char_read_resp->char_handle);
	
	if (char_read_resp->char_handle == perception_handle.char_handle1) {
		DBG_LOG(" ");
		memcpy(&perception_handle.char_data1[0],
		&char_read_resp->char_value[PERCEPTION_READ_OFFSET],
		PERCEPTION_READ_LENGTH);
		for (int i = 0; i < PERCEPTION_READ_LENGTH; i++) {
			DBG_LOG_CONT("%c", perception_handle.char_data1[i]);
		}
		DBG_LOG(" ");
	} else if (char_read_resp->char_handle == perception_handle.char_handle2) {
		DBG_LOG(" ");
		memcpy(perception_handle.char_data2,
		&char_read_resp->char_value[PERCEPTION_READ_OFFSET],
		PERCEPTION_READ_LENGTH);
		for (int i = 0; i < PERCEPTION_READ_LENGTH; i++) {
			DBG_LOG_CONT("%c", perception_handle.char_data2[i]);
		}
		DBG_LOG(" ");
	} else if (char_read_resp->char_handle == perception_handle.char_handle3) {
		DBG_LOG(" ");
		memcpy(perception_handle.char_data3,
		&char_read_resp->char_value[PERCEPTION_READ_OFFSET],
		PERCEPTION_READ_LENGTH);
		for (int i = 0; i < PERCEPTION_READ_LENGTH; i++) {
			DBG_LOG_CONT("%c", perception_handle.char_data3[i]);
		}
		DBG_LOG(" ");
	} else if (char_read_resp->char_handle == perception_handle.char_handle4) {
		DBG_LOG(" ");
		memcpy(perception_handle.char_data4,
		&char_read_resp->char_value[PERCEPTION_READ_OFFSET],
		PERCEPTION_READ_LENGTH);
		for (int i = 0; i < PERCEPTION_READ_LENGTH; i++) {
			DBG_LOG_CONT("%c", char_read_resp->char_value[i]/*perception_handle.char_data4[i]*/);
		}
		DBG_LOG(" ");
	}
	return AT_BLE_SUCCESS;
}

/**@brief Handles all Discovered characteristics of a given handler in a
* connected device
*
* Compare the characteristics UUID with proximity services whenever a
*characteristics is found
* if compare stores the characteristics handler of respective service
*
* @param[in] characteristic_found Discovered characteristics params of a
*connected device
*
*/
at_ble_status_t pxp_monitor_characteristic_found_handler(void *params)
{
	uint16_t charac_16_uuid;
	at_ble_characteristic_found_t *characteristic_found;
	characteristic_found = (at_ble_characteristic_found_t *)params;
	
	if(!ble_check_iscentral(characteristic_found->conn_handle))
	{
		return AT_BLE_FAILURE;
	}

	charac_16_uuid = (uint16_t)((characteristic_found->char_uuid.uuid[0]) |	\
	(characteristic_found->char_uuid.uuid[1] << 8));

	if (charac_16_uuid == VIBE1_INTENSITY_CHAR_UUID) {
		perception_handle.char_handle1 = characteristic_found->value_handle;
		DBG_LOG_PTS("Vibe 1 intensity characteristics: Attrib handle %x property %x handle: %x uuid : %x",
		characteristic_found->char_handle, characteristic_found->properties,
		perception_handle.char_handle1, charac_16_uuid);
	} else if (charac_16_uuid == VIBE2_INTENSITY_CHAR_UUID) {
		perception_handle.char_handle2 = characteristic_found->value_handle;
		DBG_LOG_PTS("Vibe 2 intensity characteristics: Attrib handle %x property %x handle: %x uuid : %x",
		characteristic_found->char_handle, characteristic_found->properties,
		perception_handle.char_handle2, charac_16_uuid);
	} else if (charac_16_uuid == VIBE3_INTENSITY_CHAR_UUID) {
		perception_handle.char_handle3 = characteristic_found->value_handle;
		DBG_LOG_PTS("Vibe 3 intensity characteristics: Attrib handle %x property %x handle: %x uuid : %x",
		characteristic_found->char_handle, characteristic_found->properties,
		perception_handle.char_handle3, charac_16_uuid);
	} else if (charac_16_uuid == VIBE4_INTENSITY_CHAR_UUID) {
		perception_handle.char_handle4 = characteristic_found->value_handle;
		DBG_LOG_PTS("Vibe 4 intensity characteristics: Attrib handle %x property %x handle: %x uuid : %x",
		characteristic_found->char_handle, characteristic_found->properties,
		perception_handle.char_handle4, charac_16_uuid);
	}
	return AT_BLE_SUCCESS;
}

/**@brief Registers callback for hardware timer start.
*
* @param[in] Callback for hardware timer start function.
*
* @return none.
*/
void register_hw_timer_start_func_cb(hw_timer_start_func_cb_t timer_start_fn)
{
	hw_timer_start_func_cb = timer_start_fn;
}

/**@brief Registers callback for hardware timer stop.
*
* @param[in] Callback for hardware timer stop function.
*
* @return none.
*/
void register_hw_timer_stop_func_cb(hw_timer_stop_func_cb_t timer_stop_fn)
{
	hw_timer_stop_func_cb = timer_stop_fn;
}

void register_peripheral_state_cb(peripheral_state_cb_t peripheral_state_cb)
{
	peripheral_state_callback = peripheral_state_cb;
}
