/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController+Camera.h"

@implementation ViewController (Camera)

// Called when the user allows access to the camera in setupTrackerDevices
- (void)setupColorCamera
{
    if (_avCaptureSession)
        return;
    
    // Check for camera use in settings
    bool accessAlreadyGranted = [_structureStatusUI queryCameraAuthorizationStatusWithCompletionHandler:^(BOOL granted){
        if (granted)
        {
            // Start frame grabbing if the user allowed access.
            [self startColorCamera];
        }
    }];

    if (!accessAlreadyGranted)
        return;
    
    // Use VGA color.
    NSString *sessionPreset = AVCaptureSessionPreset640x480;
    
    // Set up Capture Session.
    _avCaptureSession = [[AVCaptureSession alloc] init];
    [_avCaptureSession beginConfiguration];
    
    // Set preset session size.
    [_avCaptureSession setSessionPreset:sessionPreset];
    
    // Create a video device and input from that Device.  Add the input to the capture session.
    _videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (_videoDevice == nil)
        assert(0);
    
    // Configure Focus, Exposure, and White Balance
    NSError *error;
    
    if([_videoDevice lockForConfiguration:&error])
    {
        // Set focus at the 0.75 to get the best image quality for mid-range scene
        [_videoDevice setFocusModeLockedWithLensPosition:0.75f completionHandler:nil];
        
        // We auto-expose until tracking begins.
        [_videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        
        // Set auto-white balance
        [_videoDevice setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
        
        [_videoDevice unlockForConfiguration];
    }
    
    // Add the device to the session.
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:_videoDevice error:&error];
    if (error)
    {
        NSLog(@"Cannot initialize AVCaptureDeviceInput");
        assert(0);
    }
    
    [_avCaptureSession addInput:input]; // After this point, captureSession captureOptions are filled.
    
    // Create the output for the capture session.
    AVCaptureVideoDataOutput* dataOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    // We don't want to process late frames.
    [dataOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    // Use BGRA pixel format.
    [dataOutput setVideoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) }];
    
    __weak ViewController *weakSelf = self;
    
    // Set dispatch to be on the main thread so OpenGL can do things with the data
    [dataOutput setSampleBufferDelegate:weakSelf queue:dispatch_get_main_queue()];
    
    [_avCaptureSession addOutput:dataOutput];
    
    // Force the framerate to 30 FPS, to be in sync with Structure Sensor.
    if([_videoDevice lockForConfiguration:&error])
    {
        [_videoDevice setActiveVideoMaxFrameDuration:CMTimeMake(1, 30)];
        [_videoDevice setActiveVideoMinFrameDuration:CMTimeMake(1, 30)];
        [_videoDevice unlockForConfiguration];
    }
    
    [_avCaptureSession commitConfiguration];
}

// Called from ViewController with setupTrackerDevices, once access is granted.
- (void)startColorCamera
{
    if (_avCaptureSession == nil)
        [self setupColorCamera];
    
    // If the camera was already running then first stop it
    if (![_avCaptureSession isRunning])
        [_avCaptureSession startRunning];
}

// Called when ViewController is released.
- (void)stopColorCamera
{
    if ([_avCaptureSession isRunning])
        [_avCaptureSession stopRunning];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    // Pass color buffers directly to the driver, which will then produce synchronized depth/color pairs.
    [_sensorController frameSyncNewColorBuffer:sampleBuffer];
}

namespace {
    
    // This method locks exposure to the desired time (or as close as it can), and tries to set
    //   an ISO that gives a similar brighness (at the cost of noise, potentially).
    //
    // Important: This method assumes the current exposure/ISO ratio is appropriate for
    //            the scene.  If you didn't let the camera auto-expose, this might not be the case.
    void setManualExposureAndAutoISO (AVCaptureDevice* videoDevice, double targetExposureInSecs)
    {
        CMTime targetExposureTime = CMTimeMakeWithSeconds(targetExposureInSecs, 1000);
        CMTime currentExposureTime = videoDevice.exposureDuration;
        double exposureFactor = CMTimeGetSeconds(currentExposureTime) / targetExposureInSecs;
        
        CMTime minExposureTime = videoDevice.activeFormat.minExposureDuration;
        
        if( CMTimeCompare(minExposureTime, targetExposureTime) > 0 /* means Time1 > Time2 */ ) {
            // if minExposure is longer than targetExposure, increase our target
            targetExposureTime = minExposureTime;
        }
        
        float currentISO = videoDevice.ISO;
        float targetISO = currentISO*exposureFactor;
        float maxISO = videoDevice.activeFormat.maxISO,
        minISO = videoDevice.activeFormat.minISO;
        
        // Clamp targetISO to [minISO ... maxISO]
        targetISO = targetISO > maxISO ? maxISO : targetISO < minISO ? minISO : targetISO;
        
        [videoDevice setExposureModeCustomWithDuration: targetExposureTime
                                                   ISO: targetISO
                                     completionHandler: nil];
        
//        NSLog(@"Set exposure duration to: %f s (min=%f old=%f) and ISO to %f (max=%f old=%f ideal=%f)",
//               CMTimeGetSeconds(targetExposureTime),
//               CMTimeGetSeconds(minExposureTime),
//               CMTimeGetSeconds(currentExposureTime),
//               targetISO, maxISO, currentISO, currentISO*exposureFactor);
    }
}

// Lock exposure time and white balance. This will be called once we start tracking to make
// sure the trackers sees consistent images.
- (void)lockColorCameraExposure:(BOOL)exposureShouldBeLocked andLockWhiteBalance:(BOOL)whiteBalanceShouldBeLocked andLockFocus:(BOOL)focusShouldBeLocked
{
    NSError *error;
    
    [_videoDevice lockForConfiguration:&error];
    
    // If the manual exposure option is enabled, we've already locked exposure permanently, so do nothing here.
    if (exposureShouldBeLocked)
    {
        if (_slamState.useManualExposureAndAutoISO)
        {
            // locks the video device to 1/60th of a second exposure time
            setManualExposureAndAutoISO (_videoDevice, _slamState.targetExposureTimeInSeconds);
        }
        else
        {
            NSLog(@"Locking Camera Exposure");
            // Exposure locked to its current value.
            if([_videoDevice isExposureModeSupported:AVCaptureExposureModeLocked])
                [_videoDevice setExposureMode:AVCaptureExposureModeLocked];
        }
    }
    else
    {
        NSLog(@"Unlocking Camera Exposure");
        // Auto-exposure
        [_videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    }

    // Lock in the white balance here
    if (whiteBalanceShouldBeLocked)
    {
        // White balance locked to its current value.
        if([_videoDevice isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeLocked])
            [_videoDevice setWhiteBalanceMode:AVCaptureWhiteBalanceModeLocked];
    }
    else
    {
        // Auto-white balance.
        [_videoDevice setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
    }
    
    // Lock focus
    if (focusShouldBeLocked)
    {
        // Set focus at the 0.75 to get the best image quality for mid-range scene
        [_videoDevice setFocusModeLockedWithLensPosition:0.75f completionHandler:nil];
    }
    else
    {
        [_videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
    }
    
    [_videoDevice unlockForConfiguration];
}

@end
