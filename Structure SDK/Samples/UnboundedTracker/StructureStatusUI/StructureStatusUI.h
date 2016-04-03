/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <UIKit/UIKit.h>
#import <Structure/Structure.h>

@interface StructureStatusUI : NSObject<STSensorControllerDelegate>

- (BOOL)queryCameraAuthorizationStatusWithCompletionHandler:(void (^)(BOOL granted))handler;

- (id)initInViewController:(UIViewController*)parentView;
- (void)setSensorController:(STSensorController*)sensorController;
- (void)gotSensorConnectionResult:(STSensorControllerInitStatus)result;

@end
