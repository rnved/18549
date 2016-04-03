//
//  ViewController.m
//  Perception_v2
//
//  Created by Rishi Ved on 3/30/16.
//  Copyright © 2016 Rishi Ved. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
    NSLog(@"Changed State : %d", (int)peripheral.state);
    
    if(peripheral.state != CBPeripheralManagerStatePoweredOn) {
        return;
    }
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
            didAddService:(CBService *)service
                    error:(NSError *)error {
    
    if (error) {
        NSLog(@"Error publishing service: %@", [error localizedDescription]);
    }
}

- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral
                                       error:(NSError *)error {
    
    if (error) {
        NSLog(@"Error advertising: %@", [error localizedDescription]);
    }
}

    // MARK: Actions
- (IBAction)ConnectToBLEModule:(UIButton *)sender {
    /* TODO: Insert code to connect BLE Module and advertise custom UUID. */
    printf("Connect Button Pressed.\n");
    
    /* Declare the peripheral manager because this iOS device will function as
       the peripheral. */
    _peripheralManager =
        [[CBPeripheralManager alloc] initWithDelegate:self queue:nil options:nil];
    
    /* Create UUIDs for Custom Services and Characteristics */
    CBUUID *serviceUUID =
        [CBUUID UUIDWithString:SERVICE_UUID];
    CBUUID *vb1UUID =
        [CBUUID UUIDWithString:VB1_CHARACTERISTIC_UUID];
    CBUUID *vb2UUID =
        [CBUUID UUIDWithString:VB2_CHARACTERISTIC_UUID];
    CBUUID *vb3UUID =
        [CBUUID UUIDWithString:VB3_CHARACTERISTIC_UUID];
    CBUUID *vb4UUID =
        [CBUUID UUIDWithString:VB4_CHARACTERISTIC_UUID];
    
    /* Build Tree of Services and Characteristics.
       Note: Value should be nil if you expect it to change. */
    _intensity1 =
    [[CBMutableCharacteristic alloc] initWithType:vb1UUID
        properties:CBCharacteristicPropertyRead
        value:nil permissions:CBAttributePermissionsReadable];
    
    _intensity2 =
    [[CBMutableCharacteristic alloc] initWithType:vb2UUID
        properties:CBCharacteristicPropertyRead
        value:nil permissions:CBAttributePermissionsReadable];
    
    _intensity3 =
    [[CBMutableCharacteristic alloc] initWithType:vb3UUID
        properties:CBCharacteristicPropertyRead
        value:nil permissions:CBAttributePermissionsReadable];
    
    _intensity4 =
    [[CBMutableCharacteristic alloc] initWithType:vb4UUID
        properties:CBCharacteristicPropertyRead
        value:nil permissions:CBAttributePermissionsReadable];

    _myService = [[CBMutableService alloc] initWithType:serviceUUID primary:YES];
    
    /* Associate characteristics with the service */
    _myService.characteristics = @[_intensity1, _intensity2, _intensity3, _intensity4];
    
    /* Publish Services and Characterstics */
    [_peripheralManager addService:_myService];
    
    /* Advertise Services */
    [_peripheralManager startAdvertising:@{ CBAdvertisementDataLocalNameKey: @"Perception",
        CBAdvertisementDataServiceUUIDsKey : @[_myService.UUID] }];
    
    printf("Advertising service.\n");
    
}

@end
