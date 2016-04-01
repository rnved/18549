//
//  ViewController.h
//  Perception_v2
//
//  Created by Rishi Ved on 3/30/16.
//  Copyright © 2016 Rishi Ved. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "SERVICES.h"

@interface ViewController : UIViewController

@property (strong, nonatomic) CBPeripheralManager *peripheralManager;
@property (strong, nonatomic) CBMutableService *myService;
@property (strong, nonatomic) CBMutableCharacteristic *intensity1;
@property (strong, nonatomic) CBMutableCharacteristic *intensity2;
@property (strong, nonatomic) CBMutableCharacteristic *intensity3;
@property (strong, nonatomic) CBMutableCharacteristic *intensity4;

@end

