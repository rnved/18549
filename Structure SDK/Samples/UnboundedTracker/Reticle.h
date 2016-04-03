/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <UIKit/UIKit.h>

// Handles the small grabbing/holding icon.
@interface Reticle : UIViewController

-(id)initWithFrame:(CGRect)rect;
-(BOOL)setReticleStyle:(NSString*)style;

@end
