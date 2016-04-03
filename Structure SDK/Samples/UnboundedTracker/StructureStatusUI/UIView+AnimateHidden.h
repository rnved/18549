/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <UIKit/UIView.h>

@interface UIView (AnimateHidden)

- (void) setHidden: (BOOL) shouldBeHidden animated: (BOOL) shouldBeAnimated;
- (void) setHidden: (BOOL) shouldBeHidden animated: (BOOL) shouldBeAnimated animationDuration:(float)durationInSeconds;

@end
