/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController.h"

@interface ViewController (Camera) <AVCaptureVideoDataOutputSampleBufferDelegate>

- (void)setupColorCamera;
- (void)startColorCamera;
- (void)stopColorCamera;
- (void)lockColorCameraExposure:(BOOL)exposureShouldBeLocked andLockWhiteBalance:(BOOL)whiteBalanceShouldBeLocked andLockFocus:(BOOL)focusShouldBeLocked;

@end
