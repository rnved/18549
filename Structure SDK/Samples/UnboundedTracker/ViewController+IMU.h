/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController.h"

@interface ViewController (IMU)

-(void)setupIMU;
-(void)processDeviceMotion:(CMDeviceMotion *)motion withError:(NSError *)error;

@end
