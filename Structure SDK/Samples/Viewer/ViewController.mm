/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/


#import "ViewController.h"
#import "VIBE_GLOBALS.h"
#import <AVFoundation/AVFoundation.h>
#import <Structure/StructureSLAM.h>
#include <algorithm>

NSData *vb1Data;
NSData *vb2Data;
NSData *vb3Data;
NSData *vb4Data;

struct AppStatus
{
    NSString* const pleaseConnectSensorMessage = @"Please connect Structure Sensor.";
    NSString* const pleaseChargeSensorMessage = @"Please charge Structure Sensor.";
    NSString* const needColorCameraAccessMessage = @"This app requires camera access to capture color.\nAllow access by going to Settings → Privacy → Camera.";
    
    enum SensorStatus
    {
        SensorStatusOk,
        SensorStatusNeedsUserToConnect,
        SensorStatusNeedsUserToCharge,
    };
    
    // Structure Sensor status.
    SensorStatus sensorStatus = SensorStatusOk;
    
    // Whether iOS camera access was granted by the user.
    bool colorCameraIsAuthorized = true;
    
    // Whether there is currently a message to show.
    bool needsDisplayOfStatusMessage = false;
    
    // Flag to disable entirely status message display.
    bool statusMessageDisabled = false;
};

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate> {
    
    STSensorController *_sensorController;
    
    AVCaptureSession *_avCaptureSession;
    AVCaptureDevice *_videoDevice;

    UIImageView *_depthImageView;
    //UIImageView *_normalsImageView;
    //UIImageView *_colorImageView;
    
    uint16_t *_linearizeBuffer;
    uint8_t *_coloredDepthBuffer;
    uint8_t *_normalsBuffer;

    STNormalEstimator *_normalsEstimator;
    
    UILabel* _statusLabel;
    
    AppStatus _appStatus;
    
}

- (BOOL)connectAndStartStreaming;
- (void)convertDepthtoVibeIntensity:(STDepthFrame *)depthFrame;
- (void)renderDepthFrame:(STDepthFrame*)depthFrame;
- (void)renderNormalsFrame:(STDepthFrame*)normalsFrame;
- (void)renderColorFrame:(CMSampleBufferRef)sampleBuffer;
- (void)setupColorCamera;
- (void)startColorCamera;
- (void)stopColorCamera;

@end

@implementation ViewController

/*- (void)loadView {
    CGRect frame = [[UIScreen mainScreen] applicationFrame];
    frame.origin = CGPointZero;
    
    self.view = [[UIView alloc] initWithFrame:frame];
    self.view.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    
    self.label = [[UILabel alloc] initWithFrame:self.view.bounds];
    self.label.font = [UIFont fontWithName:@"AmericanTypewriter" size:24];
    self.label.text = @"Perception Peripheral";
    self.label.backgroundColor = [UIColor clearColor];
    self.label.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];;
    [self.view addSubview:self.label];
}*/


- (void)centralDidConnect {
    // Pulse the screen blue.
    [UIView animateWithDuration:0.1
                     animations:^{
                         self.view.backgroundColor = [UIColor blueColor];
                     }
                     completion:^(BOOL finished) {
                         [UIView animateWithDuration:0.1
                                          animations:^{
                                              self.view.backgroundColor =
                                              [UIColor colorWithWhite:0.2 alpha:1.0];
                                          }];
                     }];
}


- (void)centralDidDisconnect {
    // Pulse the screen red.
    [UIView animateWithDuration:0.1
                     animations:^{
                         self.view.backgroundColor = [UIColor redColor];
                     }
                     completion:^(BOOL finished) {
                         [UIView animateWithDuration:0.1
                                          animations:^{
                                              self.view.backgroundColor =
                                              [UIColor colorWithWhite:0.2 alpha:1.0];
                                          }];
                     }];
}


- (void)viewDidLayoutSubviews {
    [self.label sizeToFit];
    self.label.center = CGPointMake(CGRectGetMidX(self.view.bounds),
                                    CGRectGetMidY(self.view.bounds));
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _sensorController = [STSensorController sharedController];
    _sensorController.delegate = self;

    // Create three image views where we will render our frames
    
    CGRect depthFrame = [[UIScreen mainScreen] applicationFrame];
    depthFrame.origin = CGPointZero;
    /*CGRect depthFrame = self.view.frame;
    depthFrame.size.height /= 2;
    depthFrame.origin.y = self.view.frame.size.height/2;
    depthFrame.origin.x = 1;
    depthFrame.origin.x = -self.view.frame.size.width * 0.25;*/
    
    /*CGRect normalsFrame = self.view.frame;
    normalsFrame.size.height /= 2;
    normalsFrame.origin.y = self.view.frame.size.height/2;
    normalsFrame.origin.x = 1;
    normalsFrame.origin.x = self.view.frame.size.width * 0.25;*/
    
    /*CGRect colorFrame = self.view.frame;
    colorFrame.size.height /= 2;*/
    
    _linearizeBuffer = NULL;
    _coloredDepthBuffer = NULL;
    _normalsBuffer = NULL;

    _depthImageView = [[UIImageView alloc] initWithFrame:depthFrame];
    _depthImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.view addSubview:_depthImageView];
    
    /*_normalsImageView = [[UIImageView alloc] initWithFrame:normalsFrame];
    _normalsImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.view addSubview:_normalsImageView];*/
    
    /*_colorImageView = [[UIImageView alloc] initWithFrame:colorFrame];
    _colorImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.view addSubview:_colorImageView];*/

    [self setupColorCamera];
}

- (void)dealloc
{
    if (_linearizeBuffer)
        free(_linearizeBuffer);
    
    if (_coloredDepthBuffer)
        free(_coloredDepthBuffer);
    
    if (_normalsBuffer)
        free(_normalsBuffer);
}


- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    static BOOL fromLaunch = true;
    if(fromLaunch)
    {

        //
        // Create a UILabel in the center of our view to display status messages
        //
    
        // We do this here instead of in viewDidLoad so that we get the correctly size/rotation view bounds
        if (!_statusLabel) {
            
            _statusLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
            _statusLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
            _statusLabel.textAlignment = NSTextAlignmentCenter;
            _statusLabel.font = [UIFont systemFontOfSize:35.0];
            _statusLabel.numberOfLines = 2;
            _statusLabel.textColor = [UIColor whiteColor];

            [self updateAppStatusMessage];
            
            [self.view addSubview: _statusLabel];
        }

        [self connectAndStartStreaming];
        fromLaunch = false;

        // From now on, make sure we get notified when the app becomes active to restore the sensor state if necessary.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appDidBecomeActive)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
}


- (void)appDidBecomeActive
{
    [self connectAndStartStreaming];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (BOOL)connectAndStartStreaming
{
    STSensorControllerInitStatus result = [_sensorController initializeSensorConnection];
    
    BOOL didSucceed = (result == STSensorControllerInitStatusSuccess || result == STSensorControllerInitStatusAlreadyInitialized);
    if (didSucceed)
    {
        // There's no status about the sensor that we need to display anymore
        _appStatus.sensorStatus = AppStatus::SensorStatusOk;
        [self updateAppStatusMessage];
        
        // Start the color camera, setup if needed
        [self startColorCamera];
        
        // Set sensor stream quality
        STStreamConfig streamConfig = STStreamConfigDepth320x240;

        // Request that we receive depth frames with synchronized color pairs
        // After this call, we will start to receive frames through the delegate methods
        NSError* error = nil;
        BOOL optionsAreValid = [_sensorController startStreamingWithOptions:@{kSTStreamConfigKey : @(streamConfig),
                                                                              kSTFrameSyncConfigKey : @(STFrameSyncDepthAndRgb),
                                                                              kSTHoleFilterConfigKey: @TRUE} // looks better without holes
                                                                      error:&error];
        if (!optionsAreValid)
        {
            NSLog(@"Error during streaming start: %s", [[error localizedDescription] UTF8String]);
            return false;
        }
        
        // Allocate the depth -> surface normals converter class
        _normalsEstimator = [[STNormalEstimator alloc] init];
    }
    else
    {
        if (result == STSensorControllerInitStatusSensorNotFound)
            NSLog(@"[Debug] No Structure Sensor found!");
        else if (result == STSensorControllerInitStatusOpenFailed)
            NSLog(@"[Error] Structure Sensor open failed.");
        else if (result == STSensorControllerInitStatusSensorIsWakingUp)
            NSLog(@"[Debug] Structure Sensor is waking from low power.");
        else if (result != STSensorControllerInitStatusSuccess)
            NSLog(@"[Debug] Structure Sensor failed to init with status %d.", (int)result);
        
        _appStatus.sensorStatus = AppStatus::SensorStatusNeedsUserToConnect;
        [self updateAppStatusMessage];
    }
    

    
    //Usage of wireless debugging API
    //NSError* error = nil;
    //[STWirelessLog broadcastLogsToWirelessConsoleAtAddress:@"128.237.240.174" usingPort:4999 error:&error];
    //if (error) NSLog(@"Oh no! Can't start wireless log: %@", [error localizedDescription]);

    return didSucceed;
    
}

- (void)showAppStatusMessage:(NSString *)msg
{
    _appStatus.needsDisplayOfStatusMessage = true;
    [self.view.layer removeAllAnimations];
    
    [_statusLabel setText:msg];
    [_statusLabel setHidden:NO];
    
    // Progressively show the message label.
    [self.view setUserInteractionEnabled:false];
    [UIView animateWithDuration:0.5f animations:^{
        _statusLabel.alpha = 1.0f;
    }completion:nil];
}

- (void)hideAppStatusMessage
{
    
    _appStatus.needsDisplayOfStatusMessage = false;
    [self.view.layer removeAllAnimations];
    
    [UIView animateWithDuration:0.5f
                     animations:^{
                         _statusLabel.alpha = 0.0f;
                     }
                     completion:^(BOOL finished) {
                         // If nobody called showAppStatusMessage before the end of the animation, do not hide it.
                         if (!_appStatus.needsDisplayOfStatusMessage)
                         {
                             [_statusLabel setHidden:YES];
                             [self.view setUserInteractionEnabled:true];
                         }
                     }];
}

-(void)updateAppStatusMessage
{
    // Skip everything if we should not show app status messages (e.g. in viewing state).
    if (_appStatus.statusMessageDisabled)
    {
        [self hideAppStatusMessage];
        return;
    }
    
    // First show sensor issues, if any.
    switch (_appStatus.sensorStatus)
    {
        case AppStatus::SensorStatusOk:
        {
            break;
        }
            
        case AppStatus::SensorStatusNeedsUserToConnect:
        {
            [self showAppStatusMessage:_appStatus.pleaseConnectSensorMessage];
            return;
        }
            
        case AppStatus::SensorStatusNeedsUserToCharge:
        {
            [self showAppStatusMessage:_appStatus.pleaseChargeSensorMessage];
            return;
        }
    }
    
    // Then show color camera permission issues, if any.
    if (!_appStatus.colorCameraIsAuthorized)
    {
        [self showAppStatusMessage:_appStatus.needColorCameraAccessMessage];
        return;
    }
    
    // If we reach this point, no status to show.
    [self hideAppStatusMessage];
}

-(bool) isConnectedAndCharged
{
    return [_sensorController isConnected] && ![_sensorController isLowPower];
}


#pragma mark -
#pragma mark Structure SDK Delegate Methods

- (void)sensorDidDisconnect
{
    NSLog(@"Structure Sensor disconnected!");

    _appStatus.sensorStatus = AppStatus::SensorStatusNeedsUserToConnect;
    [self updateAppStatusMessage];
    
    // Stop the color camera when there isn't a connected Structure Sensor
    [self stopColorCamera];
}

- (void)sensorDidConnect
{
    NSLog(@"Structure Sensor connected!");
    [self connectAndStartStreaming];
}

- (void)sensorDidLeaveLowPowerMode
{
    _appStatus.sensorStatus = AppStatus::SensorStatusNeedsUserToConnect;
    [self updateAppStatusMessage];
}


- (void)sensorBatteryNeedsCharging
{
    // Notify the user that the sensor needs to be charged.
    _appStatus.sensorStatus = AppStatus::SensorStatusNeedsUserToCharge;
    [self updateAppStatusMessage];
}

- (void)sensorDidStopStreaming:(STSensorControllerDidStopStreamingReason)reason
{
    //If needed, change any UI elements to account for the stopped stream

    // Stop the color camera when we're not streaming from the Structure Sensor
    [self stopColorCamera];

}

- (void)sensorDidOutputDepthFrame:(STDepthFrame *)depthFrame
{
    [self renderDepthFrame:depthFrame];
    [self convertDepthtoVibeIntensity:depthFrame];
    [self renderNormalsFrame:depthFrame];
}

// This synchronized API will only be called when two frames match. Typically, timestamps are within 1ms of each other.
// Two important things have to happen for this method to be called:
// Tell the SDK we want framesync with options @{kSTFrameSyncConfigKey : @(STFrameSyncDepthAndRgb)} in [STSensorController startStreamingWithOptions:error:]
// Give the SDK color frames as they come in:     [_ocSensorController frameSyncNewColorBuffer:sampleBuffer];
- (void)sensorDidOutputSynchronizedDepthFrame:(STDepthFrame *)depthFrame
                                andColorFrame:(STColorFrame *)colorFrame
{
    [self renderDepthFrame:depthFrame];
    [self convertDepthtoVibeIntensity:depthFrame];
    [self renderNormalsFrame:depthFrame];
    [self renderColorFrame:colorFrame.sampleBuffer];
}


#pragma mark -
#pragma mark Rendering

const uint16_t maxShiftValue = 2048;

- (void)populateLinearizeBuffer
{
    _linearizeBuffer = (uint16_t*)malloc((maxShiftValue + 1) * sizeof(uint16_t));
    
    for (int i=0; i <= maxShiftValue; i++)
    {
        float v = i/ (float)maxShiftValue;
        v = powf(v, 3)* 6;
        _linearizeBuffer[i] = v*6*256;
    }
}

// This function is equivalent to calling [STDepthAsRgba convertDepthFrameToRgba] with the
// STDepthToRgbaStrategyRedToBlueGradient strategy. Not using the SDK here for didactic purposes.
- (void)convertShiftToRGBA:(const uint16_t*)shiftValues depthValuesCount:(size_t)depthValuesCount
{
    int valSize = sizeof(shiftValues);
    
    for (size_t i = 0; i < depthValuesCount; i++)
    {
        // We should not get higher values than maxShiftValue, but let's stay on the safe side.
        uint16_t boundedShift = std::min (shiftValues[i], maxShiftValue);
        
        // Use a lookup table to make the non-linear input values vary more linearly with metric depth
        int linearizedDepth = _linearizeBuffer[boundedShift];
        
        // Use the upper byte of the linearized shift value to choose a base color
        // Base colors range from: (closest) White, Red, Orange, Yellow, Green, Cyan, Blue, Black (farthest)
        int lowerByte = (linearizedDepth & 0xff);
        
        // Use the lower byte to scale between the base colors
        int upperByte = (linearizedDepth >> 8);
        
        switch (upperByte)
        {
            case 0:
                _coloredDepthBuffer[4*i+0] = 255;
                _coloredDepthBuffer[4*i+1] = 255-lowerByte;
                _coloredDepthBuffer[4*i+2] = 255-lowerByte;
                _coloredDepthBuffer[4*i+3] = 255;
                break;
            case 1:
                _coloredDepthBuffer[4*i+0] = 255;
                _coloredDepthBuffer[4*i+1] = lowerByte;
                _coloredDepthBuffer[4*i+2] = 0;
                break;
            case 2:
                _coloredDepthBuffer[4*i+0] = 255-lowerByte;
                _coloredDepthBuffer[4*i+1] = 255;
                _coloredDepthBuffer[4*i+2] = 0;
                break;
            case 3:
                _coloredDepthBuffer[4*i+0] = 0;
                _coloredDepthBuffer[4*i+1] = 255;
                _coloredDepthBuffer[4*i+2] = lowerByte;
                break;
            case 4:
                _coloredDepthBuffer[4*i+0] = 0;
                _coloredDepthBuffer[4*i+1] = 255-lowerByte;
                _coloredDepthBuffer[4*i+2] = 255;
                break;
            case 5:
                _coloredDepthBuffer[4*i+0] = 0;
                _coloredDepthBuffer[4*i+1] = 0;
                _coloredDepthBuffer[4*i+2] = 255-lowerByte;
                break;
            default:
                _coloredDepthBuffer[4*i+0] = 0;
                _coloredDepthBuffer[4*i+1] = 0;
                _coloredDepthBuffer[4*i+2] = 0;
                break;
        }
    }
}


-(void) convertDepthtoVibeIntensity:(STDepthFrame *)depthFrame
{
    //SHIT
    size_t cols = depthFrame.width;
    size_t rows = depthFrame.height;
    float* depthValues = depthFrame.depthInMillimeters;
    int minDepth = 20000000;
    int min_pixel = 0;
    for (int i = 0; i < cols*rows; i++)
    {
        int depthValue = (int)depthValues[i];
        if(depthValue < minDepth & depthValue != isnan(depthValue))
        {
            minDepth = depthValue;
            min_pixel = i;
        }
    }
    int row = min_pixel / cols;
    int col = min_pixel % cols;
    
    // Categorization at Pixel Level
    NSString *hor = @"LEFT"; //Left, CENTER or Right
    
    /*
    if (col < 160) {
        hor = @"LEFT";
    }
    else {
        hor = @"RIGHT";
    }
    */
    
    if (col < 105) {
        hor = @"LEFT";
    }
    else if (col >= 110 & col <= 210) {
        hor = @"CENTER";
    }
    else {
        hor = @"RIGHT";
    }
    
    NSString *ver = @"TOP"; //Top or Bottom
    
    if (row < 120) {
        ver = @"TOP";
    }
    else {
        ver = @"BOTTOM";
    }
    
    // Categorization of Depth
    int intensity = 0;
    
    // very close = black out on color frame
    if (minDepth == 20000000) {
        intensity = 10;
    }
    else if (minDepth < 250) {
        intensity = 10;
    }
    else if (minDepth < 500 && minDepth >= 250) {
        intensity = 9;
    }
    else if (minDepth < 750 && minDepth >= 500) {
        intensity = 8;
    }
    else if (minDepth < 1000 && minDepth >= 750) {
        intensity = 7;
    }
    /*
    else if (minDepth < 1250 && minDepth >= 1000) {
        intensity = 6;
    }
    else if (minDepth < 1500 && minDepth >= 1250) {
        intensity = 5;
    }
    */
    
    // far
    else {
        intensity = 0;
    }

    int vb1_intensity = 0;
    int vb2_intensity = 0;
    int vb3_intensity = 0;
    int vb4_intensity = 0;
    
    // Categorization of Vibe motors
    if ([ver isEqualToString:@"TOP"] & [hor isEqualToString:@"LEFT"] )  //TOP LEFT
    {
        vb1_intensity = intensity;
        vb2_intensity = 0;
        vb3_intensity = 0;
        vb4_intensity = 0;
    }
    else if ([ver isEqualToString:@"TOP"] & [hor isEqualToString:@"CENTER"] )  //TOP CENTER
    {
        vb1_intensity = intensity;
        vb2_intensity = intensity;
        vb3_intensity = 0;
        vb4_intensity = 0;
    }
    else if ([ver isEqualToString:@"TOP"] & [hor isEqualToString:@"RIGHT"] )  //TOP RIGHT
    {
        vb1_intensity = 0;
        vb2_intensity = intensity;
        vb3_intensity = 0;
        vb4_intensity = 0;
    }
    else if ([ver isEqualToString:@"BOTTOM"] & [hor isEqualToString:@"LEFT"] )  //BOTTOM LEFT
    {
        vb1_intensity = 0;
        vb2_intensity = 0;
        vb3_intensity = intensity;
        vb4_intensity = 0;
    }
    else if ([ver isEqualToString:@"BOTTOM"] & [hor isEqualToString:@"CENTER"] )// BOTTOM CENTER
    {
        vb1_intensity = 0;
        vb2_intensity = 0;
        vb3_intensity = intensity;
        vb4_intensity = intensity;
    }
    else if ([ver isEqualToString:@"BOTTOM"] & [hor isEqualToString:@"RIGHT"] )// BOTTOM RIGHT
    {
        vb1_intensity = 0;
        vb2_intensity = 0;
        vb3_intensity = 0;
        vb4_intensity = intensity;
    }
    else { // Exception Case
        vb1_intensity = 0;
        vb2_intensity = 0;
        vb3_intensity = 0;
        vb4_intensity = 0;
    }

    
    NSLog(@"( %d mm) at %@ & %@:: vb1=%d, vb2=%d, vb3=%d, vb4=%d", minDepth, ver, hor, vb1_intensity, vb2_intensity, vb3_intensity, vb4_intensity);

    //      deliver intensity values to BLE
    //
    //      Screen mapping of vibe motors:
    //
    //      vb1Data1 | vb1Data2
    //      ———————————————————
    //      vb1Data3 | vb1Data4
    //
    
    vb1Data = [NSData dataWithBytes:& vb1_intensity length:sizeof(vb1_intensity)];
    vb2Data = [NSData dataWithBytes:& vb2_intensity length:sizeof(vb2_intensity)];
    vb3Data = [NSData dataWithBytes:& vb3_intensity length:sizeof(vb3_intensity)];
    vb4Data = [NSData dataWithBytes:& vb4_intensity length:sizeof(vb4_intensity)];
}


- (void)renderDepthFrame:(STDepthFrame *)depthFrame
{
    size_t cols = depthFrame.width;
    size_t rows = depthFrame.height;
    
    if (_linearizeBuffer == NULL || _normalsBuffer == NULL)
    {
        [self populateLinearizeBuffer];
        _coloredDepthBuffer = (uint8_t*)malloc(cols * rows * 4);
    }
    
    // Conversion of 16-bit non-linear shift depth values to 32-bit RGBA
    //
    // Adapted from: https://github.com/OpenKinect/libfreenect/blob/master/examples/glview.c
    //
    [self convertShiftToRGBA:depthFrame.shiftData depthValuesCount:cols * rows];
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGBitmapInfo bitmapInfo;
    bitmapInfo = (CGBitmapInfo)kCGImageAlphaNoneSkipLast;
    bitmapInfo |= kCGBitmapByteOrder32Big;
    
    NSData *data = [NSData dataWithBytes:_coloredDepthBuffer length:cols * rows * 4];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data); //toll-free ARC bridging
    
    CGImageRef imageRef = CGImageCreate(cols,                       //width
                                       rows,                        //height
                                       8,                           //bits per component
                                       8 * 4,                       //bits per pixel
                                       cols * 4,                    //bytes per row
                                       colorSpace,                  //Quartz color space
                                       bitmapInfo,                  //Bitmap info (alpha channel?, order, etc)
                                       provider,                    //Source of data for bitmap
                                       NULL,                        //decode
                                       false,                       //pixel interpolation
                                       kCGRenderingIntentDefault);  //rendering intent
    
    // Assign CGImage to UIImage
    _depthImageView.image = [UIImage imageWithCGImage:imageRef];
    
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
}

- (void) renderNormalsFrame: (STDepthFrame*) depthFrame
{
    // Estimate surface normal direction from depth float values
    STNormalFrame *normalsFrame = [_normalsEstimator calculateNormalsWithDepthFrame:depthFrame];
    
    size_t cols = normalsFrame.width;
    size_t rows = normalsFrame.height;
    
    // Convert normal unit vectors (ranging from -1 to 1) to RGB (ranging from 0 to 255)
    // Z can be slightly positive in some cases too!
    if (_normalsBuffer == NULL)
    {
        _normalsBuffer = (uint8_t*)malloc(cols * rows * 4);
    }
    
    for (size_t i = 0; i < cols * rows; i++)
    {
        _normalsBuffer[4*i+0] = (uint8_t)( ( ( normalsFrame.normals[i].x / 2 ) + 0.5 ) * 255);
        _normalsBuffer[4*i+1] = (uint8_t)( ( ( normalsFrame.normals[i].y / 2 ) + 0.5 ) * 255);
        _normalsBuffer[4*i+2] = (uint8_t)( ( ( normalsFrame.normals[i].z / 2 ) + 0.5 ) * 255);
    }
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGBitmapInfo bitmapInfo;
    bitmapInfo = (CGBitmapInfo)kCGImageAlphaNoneSkipFirst;
    bitmapInfo |= kCGBitmapByteOrder32Little;
    
    NSData *data = [NSData dataWithBytes:_normalsBuffer length:cols * rows * 4];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    
    CGImageRef imageRef = CGImageCreate(cols,
                                        rows,
                                        8,
                                        8 * 4,
                                        cols * 4,
                                        colorSpace,
                                        bitmapInfo,
                                        provider,
                                        NULL,
                                        false,
                                        kCGRenderingIntentDefault);
    
    //_normalsImageView.image = [[UIImage alloc] initWithCGImage:imageRef];
    
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);

}

- (void)renderColorFrame:(CMSampleBufferRef)sampleBuffer
{

    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    size_t cols = CVPixelBufferGetWidth(pixelBuffer);
    size_t rows = CVPixelBufferGetHeight(pixelBuffer);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    unsigned char *ptr = (unsigned char *) CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    
    NSData *data = [[NSData alloc] initWithBytes:ptr length:rows*cols*4];
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    CGBitmapInfo bitmapInfo;
    bitmapInfo = (CGBitmapInfo)kCGImageAlphaNoneSkipFirst;
    bitmapInfo |= kCGBitmapByteOrder32Little;
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    
    CGImageRef imageRef = CGImageCreate(cols,
                                        rows,
                                        8,
                                        8 * 4,
                                        cols*4,
                                        colorSpace,
                                        bitmapInfo,
                                        provider,
                                        NULL,
                                        false,
                                        kCGRenderingIntentDefault);
    
    //_colorImageView.image = [[UIImage alloc] initWithCGImage:imageRef];
    
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
}



#pragma mark -  AVFoundation

- (bool)queryCameraAuthorizationStatusAndNotifyUserIfNotGranted
{
    const NSUInteger numCameras = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count];
    
    if (0 == numCameras)
        return false; // This can happen even on devices that include a camera, when camera access is restricted globally.

    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    
    if (authStatus != AVAuthorizationStatusAuthorized)
    {
        NSLog(@"Not authorized to use the camera!");
        
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                 completionHandler:^(BOOL granted)
         {
             // This block fires on a separate thread, so we need to ensure any actions here
             // are sent to the right place.
             
             // If the request is granted, let's try again to start an AVFoundation session. Otherwise, alert
             // the user that things won't go well.
             if (granted)
             {
                 
                 dispatch_async(dispatch_get_main_queue(), ^(void) {
                     
                     [self startColorCamera];
                     
                     _appStatus.colorCameraIsAuthorized = true;
                     [self updateAppStatusMessage];
                     
                 });
                 
             }
             
         }];
        
        return false;
    }

    return true;
    
}

- (void)setupColorCamera
{
    // If already setup, skip it
    if (_avCaptureSession)
        return;
    
    bool cameraAccessAuthorized = [self queryCameraAuthorizationStatusAndNotifyUserIfNotGranted];
    
    if (!cameraAccessAuthorized)
    {
        _appStatus.colorCameraIsAuthorized = false;
        [self updateAppStatusMessage];
        return;
    }
    
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
    
    // Use auto-exposure, and auto-white balance and set the focus to infinity.
    if([_videoDevice lockForConfiguration:&error])
    {
        // Allow exposure to change
        if ([_videoDevice isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
            [_videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        
        // Allow white balance to change
        if ([_videoDevice isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance])
            [_videoDevice setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
        
        // Set focus at the maximum position allowable (e.g. "near-infinity") to get the
        // best color/depth alignment.
        [_videoDevice setFocusModeLockedWithLensPosition:1.0f completionHandler:nil];
        
        [_videoDevice unlockForConfiguration];
    }
    
    //  Add the device to the session.
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:_videoDevice error:&error];
    if (error)
    {
        NSLog(@"Cannot initialize AVCaptureDeviceInput");
        assert(0);
    }
    
    [_avCaptureSession addInput:input]; // After this point, captureSession captureOptions are filled.
    
    //  Create the output for the capture session.
    AVCaptureVideoDataOutput* dataOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    // We don't want to process late frames.
    [dataOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    // Use BGRA pixel format.
    [dataOutput setVideoSettings:[NSDictionary
                                  dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                  forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    
    // Set dispatch to be on the main thread so OpenGL can do things with the data
    [dataOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    [_avCaptureSession addOutput:dataOutput];
    
    if([_videoDevice lockForConfiguration:&error])
    {
        [_videoDevice setActiveVideoMaxFrameDuration:CMTimeMake(1, 30)];
        [_videoDevice setActiveVideoMinFrameDuration:CMTimeMake(1, 30)];
        [_videoDevice unlockForConfiguration];
    }
    
    [_avCaptureSession commitConfiguration];
}

- (void)startColorCamera
{
    if (_avCaptureSession && [_avCaptureSession isRunning])
        return;
    
    // Re-setup so focus is lock even when back from background
    if (_avCaptureSession == nil)
        [self setupColorCamera];
    
    // Start streaming color images.
    [_avCaptureSession startRunning];
}

- (void)stopColorCamera
{
    if ([_avCaptureSession isRunning])
    {
        // Stop the session
        [_avCaptureSession stopRunning];
    }
    
    _avCaptureSession = nil;
    _videoDevice = nil;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    // Pass into the driver. The sampleBuffer will return later with a synchronized depth or IR pair.
    [_sensorController frameSyncNewColorBuffer:sampleBuffer];
}


@end
