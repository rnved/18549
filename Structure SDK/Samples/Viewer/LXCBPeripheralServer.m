#import <CoreBluetooth/CoreBluetooth.h>
#import "LXCBPeripheralServer.h"
#import "UUIDs.h"
#import "VIBE_GLOBALS.h"

NSData *vb1Data;
NSData *vb2Data;
NSData *vb3Data;
NSData *vb4Data;

@interface LXCBPeripheralServer () <
    CBPeripheralManagerDelegate,
    UIAlertViewDelegate>

@property(nonatomic, strong) CBPeripheralManager *peripheral;
@property(nonatomic, strong) CBMutableCharacteristic *vb1;
@property(nonatomic, strong) CBMutableCharacteristic *vb2;
@property(nonatomic, strong) CBMutableCharacteristic *vb3;
@property(nonatomic, strong) CBMutableCharacteristic *vb4;
@property(nonatomic, assign) BOOL serviceRequiresRegistration;
@property(nonatomic, strong) CBMutableService *service;
@property(nonatomic, strong) NSData *pendingData;
@property(nonatomic, strong) CBCharacteristic *pendingCharacteristic;

@end

@implementation LXCBPeripheralServer

+ (BOOL)isBluetoothSupported {
  // Only for iOS 6.0
  if (NSClassFromString(@"CBPeripheralManager") == nil) {
    return NO;
  }

  // TODO: Make a check to see if the CBPeripheralManager is in unsupported state.
  return YES;
}

- (id)init {
  return [self initWithDelegate:nil];
}

- (id)initWithDelegate:(id<LXCBPeripheralServerDelegate>)delegate {
  self = [super init];
  if (self) {
    self.peripheral =
        [[CBPeripheralManager alloc] initWithDelegate:self queue:nil];
    self.delegate = delegate;
  }
  return self;
}

#pragma mark -

- (void)enableService {
  // If the service is already registered, we need to re-register it again.
  if (self.service) {
    [self.peripheral removeService:self.service];
  }

  // Create a BTLE Peripheral Service and set it to be the primary. If it
  // is not set to the primary, it will not be found when the app is in the
  // background.
  self.service = [[CBMutableService alloc]
                    initWithType:self.serviceUUID primary:YES];

  // Set up the vibe motor characteristics in the service. These characteristics are only
  // readable through read requests (CBCharacteristicsPropertyRead) and has
  // no default value set.
  //
  // There is no need to set the permission on characteristic.
  self.vb1 =
      [[CBMutableCharacteristic alloc]
          initWithType:self.vb1UUID
            properties:CBCharacteristicPropertyNotify|CBCharacteristicPropertyRead|CBCharacteristicPropertyIndicate
                 value:nil
           permissions:CBAttributePermissionsReadable];
    
  self.vb2 =
      [[CBMutableCharacteristic alloc]
          initWithType:self.vb2UUID
            properties:CBCharacteristicPropertyNotify|CBCharacteristicPropertyRead|CBCharacteristicPropertyIndicate
                 value:nil
           permissions:CBAttributePermissionsReadable];
    
  self.vb3 =
      [[CBMutableCharacteristic alloc]
          initWithType:self.vb3UUID
            properties:CBCharacteristicPropertyNotify|CBCharacteristicPropertyRead|CBCharacteristicPropertyIndicate
                 value:nil
           permissions:CBAttributePermissionsReadable];
    
  self.vb4 =
      [[CBMutableCharacteristic alloc]
          initWithType:self.vb4UUID
            properties:CBCharacteristicPropertyNotify|CBCharacteristicPropertyRead|CBCharacteristicPropertyIndicate
                 value:nil
           permissions:CBAttributePermissionsReadable];

  // Assign the characteristic.
  self.service.characteristics =
      [NSArray arrayWithObjects:self.vb1, self.vb2, self.vb3, self.vb4, nil];

  // Add the service to the peripheral manager.
  [self.peripheral addService:self.service];
    
  int integer = 0;
  vb1Data = [NSData dataWithBytes:& integer length:sizeof(integer)];
  vb2Data = [NSData dataWithBytes:& integer length:sizeof(integer)];
  vb3Data = [NSData dataWithBytes:& integer length:sizeof(integer)];
  vb4Data = [NSData dataWithBytes:& integer length:sizeof(integer)];
    
}

- (void)disableService {
  [self.peripheral removeService:self.service];
  self.service = nil;
  [self stopAdvertising];
}


// Called when the BTLE advertisments should start. We don't take down
// the advertisments unless the user switches us off.
- (void)startAdvertising {
  if (self.peripheral.isAdvertising) {
    [self.peripheral stopAdvertising];
  }

  NSDictionary *advertisment = @{
      CBAdvertisementDataServiceUUIDsKey : @[self.serviceUUID],
      CBAdvertisementDataLocalNameKey: self.serviceName
  };
  [self.peripheral startAdvertising:advertisment];
}

- (void)stopAdvertising {
  [self.peripheral stopAdvertising];
}

- (BOOL)isAdvertising {
  return [self.peripheral isAdvertising];
}


#pragma mark -

- (void)sendToSubscribers:(NSData *)data
     chosenCharacteristic:(CBCharacteristic *)characteristic{
  if (self.peripheral.state != CBPeripheralManagerStatePoweredOn) {
    NSLog(@"sendToSubscribers: peripheral not ready for sending state: %ld", (long)self.peripheral.state);
    return;
  }

  BOOL success = [self.peripheral updateValue:data
                            forCharacteristic:(CBMutableCharacteristic *)characteristic
                         onSubscribedCentrals:nil];
  if (!success) {
    NSLog(@"Failed to send data, buffering data for retry once ready.");
    self.pendingData = data;
    self.pendingCharacteristic = characteristic;
    return;
  }
}

- (void)applicationDidEnterBackground {
  // Deliberately continue advertising so that it still remains discoverable.
}

- (void)applicationWillEnterForeground {
  NSLog(@"applicationWillEnterForeground.");
  // I once thought that it would be good to re-advertise and re-enable
  // the services when coming in the foreground, but it does more harm than
  // good. If we do that, then if there was a Central subscribing to a
  // characteristic, that would get reset.
  //
  // So here we deliberately avoid re-enabling or re-advertising the service.
}

#pragma mark - CBPeripheralManagerDelegate

- (void)peripheralManager:(CBPeripheralManager *)peripheral
            didAddService:(CBService *)service
                    error:(NSError *)error {
  
  // As soon as the service is added, we should start advertising.
  [self startAdvertising];
}

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
  switch (peripheral.state) {
    case CBPeripheralManagerStatePoweredOn:
      NSLog(@"peripheralStateChange: Powered On");
      // As soon as the peripheral/bluetooth is turned on, start initializing
      // the service.
      [self enableService];
      break;
    case CBPeripheralManagerStatePoweredOff: {
      NSLog(@"peripheralStateChange: Powered Off");
      [self disableService];
      self.serviceRequiresRegistration = YES;
      break;
    }
    case CBPeripheralManagerStateResetting: {
      NSLog(@"peripheralStateChange: Resetting");
      self.serviceRequiresRegistration = YES;
      break;
    }
    case CBPeripheralManagerStateUnauthorized: {
      NSLog(@"peripheralStateChange: Deauthorized");
      [self disableService];
      self.serviceRequiresRegistration = YES;
      break;
    }
    case CBPeripheralManagerStateUnsupported: {
      NSLog(@"peripheralStateChange: Unsupported");
      self.serviceRequiresRegistration = YES;
      // TODO: Give user feedback that Bluetooth is not supported.
      break;
    }
    case CBPeripheralManagerStateUnknown:
      NSLog(@"peripheralStateChange: Unknown");
      break;
    default:
      break;
  }
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
                  central:(CBCentral *)central
didSubscribeToCharacteristic:(CBCharacteristic *)characteristic {
  NSLog(@"didSubscribe: %@", characteristic.UUID);
  //LXCBLog(@"didSubscribe: - Central: %@", central.UUID);
  [self.delegate peripheralServer:self centralDidSubscribe:central chosenCharacteristic:characteristic];
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
                  central:(CBCentral *)central
didUnsubscribeFromCharacteristic:(CBCharacteristic *)characteristic {
  //LXCBLog(@"didUnsubscribe: %@", central.UUID);
  [self.delegate peripheralServer:self centralDidUnsubscribe:central];
}

- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral
                                       error:(NSError *)error {
  if (error) {
    NSLog(@"didStartAdvertising: Error: %@", error);
    return;
  }
  NSLog(@"didStartAdvertising");
}

- (void)peripheralManagerIsReadyToUpdateSubscribers:(CBPeripheralManager *)peripheral {
  NSLog(@"isReadyToUpdateSubscribers");
  if (self.pendingData) {
    NSData *data = [self.pendingData copy];
    self.pendingData = nil;
    CBMutableCharacteristic *characteristic = [self.pendingCharacteristic copy];
    self.pendingCharacteristic = nil;
    [self sendToSubscribers:data chosenCharacteristic:characteristic];
  }
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
  didReceiveReadRequest:(CBATTRequest *)request {
  NSLog(@"didReceiveReadRequest");
    
  CBCharacteristic *characteristic = nil;
    
  if([request.characteristic.UUID isEqual:self.vb1.UUID]) {
    self.vb1.value = vb1Data;
    characteristic = self.vb1;
  } else if ([request.characteristic.UUID isEqual:self.vb2.UUID]) {
      self.vb2.value = vb2Data;
      characteristic = self.vb2;
  } else if ([request.characteristic.UUID isEqual:self.vb3.UUID]) {
      self.vb3.value = vb3Data;
      characteristic = self.vb3;
  } else if ([request.characteristic.UUID isEqual:self.vb4.UUID]) {
      self.vb4.value = vb4Data;
      characteristic = self.vb4;
  } else {
      NSLog(@"Not a valid read request. Did not match any characteristic");
      [peripheral respondToRequest:request withResult:CBATTErrorAttributeNotFound];
      return;
  }
    
  if(request.offset > characteristic.value.length) {
  [_peripheral respondToRequest:request withResult:CBATTErrorInvalidOffset];
    return;
  }
  
  request.value = [characteristic.value
      subdataWithRange:NSMakeRange(request.offset,
      characteristic.value.length - request.offset)];
    
  [peripheral respondToRequest:request withResult:CBATTErrorSuccess];
}

@end
