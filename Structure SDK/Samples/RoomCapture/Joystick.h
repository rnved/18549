/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <UIKit/UIKit.h>

@interface Joystick : UIViewController

@property(nonatomic, readonly) BOOL isSelected;
@property(nonatomic, readonly) BOOL isEnabled;
@property(nonatomic, readonly) float theta;
@property(nonatomic, readonly) float radius;

- (id)initWithFrame:(CGRect)frame backgroundImage:(NSString*)backgroundImageName joystickImage:(NSString*)joystickImageName;
- (void)setEnabled:(BOOL)enabled;

@end
