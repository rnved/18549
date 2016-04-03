/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

// StructureStatusUI contains all the UI for Structure Sensor status feedback,
// as required as part of the Structure Sensor App Submission process.
// This is:
//   - battery status
//   - calibration overlay
//   - camera allowance setting
//   - structure connected status/first time "get structure" message.
//
// A developer may copy this collection of files into each new structure app,
// and write code in the parent view controller to instantiate and send it events.
//
// The only modification users may want to do is change the default location of where
// the UI elements are placed, but that's just changing the hard-coded numbers in the frame.

#import "StructureStatusUI.h"
#import "UIView+AnimateHidden.h"

#import "CalibrationOverlay.h"
#import "LocalStoreHelper.h"

@interface StructureStatusUI ()
{
    NSTimer *_updateBatteryDisplayTimer;
    STSensorController *_sensorController;
    
    UIViewController *_parentViewController;
    
    // UI Feedback elements
    UIImageView *_sensorBatteryIcon;
    UILabel *_structureMessageLabel;
    CalibrationOverlay* _calibrationOverlay;
    UIView *_getStructureView;
    
    BOOL    _hasStructureSensorConnected;
}
@end

#define NOTIFICATION_X 664
#define NOTIFICATION_Y 40
#define CAMERA_ACCESS_ALERT_TAG 102491

// ALWAYS_SHOW_EVERYTHING is useful for debugging StructureStatusUI without the sensor being in the state so everything is shown.
const bool ALWAYS_SHOW_EVERYTHING = NO;

@implementation StructureStatusUI

+ (void)applyUIStyle:(UIView*)view
{
    [view setBackgroundColor:[UIColor colorWithRed:0 green:0 blue:0 alpha:0.9]];
    
    view.layer.cornerRadius = 10.0f;
    
    UIColor *borderColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    [view.layer setBorderColor:borderColor.CGColor];
    [view.layer setBorderWidth:1.0f];
}

- (void)cameraAccessDenied
{
    NSString *alertTitle = @"Camera Access Blocked";
    NSString *alertText = @"Please turn on Camera and Photos access in Settings.";
    NSString *alertButtonTitle = @"Open Settings";
    
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                   message:alertText
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:alertButtonTitle
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction * action) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
        }];
    
    [alert addAction:defaultAction];
    [_parentViewController presentViewController:alert animated:YES completion:nil];

}

- (void)cameraAccessGloballyRestricted
{
    NSString *alertTitle = @"Camera Access Restricted";
    NSString *alertText = @"Please turn off the Camera restriction in Settings → General → Restrictions.";
    NSString *alertButtonTitle = @"Open Settings";
    
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                   message:alertText
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:alertButtonTitle
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * action) {
                                                              [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
                                                          }];
    
    [alert addAction:defaultAction];
    [_parentViewController presentViewController:alert animated:YES completion:nil];
    
}

- (BOOL)queryCameraAuthorizationStatusWithCompletionHandler:(void (^)(BOOL granted))handler
{
    const NSUInteger numCameras = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count];
    
    if (0 == numCameras)
    {
        [self cameraAccessGloballyRestricted];
        return NO; // This can happen even on devices that include a camera, when camera access is restricted globally.
    }

    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    
    if (authStatus != AVAuthorizationStatusAuthorized)
    {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                 completionHandler:
         ^(BOOL granted) {
             // This block fires on a separate thread, so we need to ensure any actions here
             // are sent to the right place.
             dispatch_async(dispatch_get_main_queue(), ^(void) {
                 if (!granted)
                     [self cameraAccessDenied];
                 
                 if (handler != nil)
                     handler(granted);
             });
         }];
        
        return NO;
    }
    
    return YES;
}

# pragma mark - initialization

- (id)initInViewController:(UIViewController*)parentViewController
{
    _parentViewController = parentViewController;
    
    [self initBatteryIcon];
    [self initGetStructureView];
    [self initStructureMessageLabel];
    
    _calibrationOverlay = [CalibrationOverlay calibrationOverlaySubviewOf:_parentViewController.view
        atOrigin:CGPointMake(NOTIFICATION_X, NOTIFICATION_Y)];
    [StructureStatusUI applyUIStyle:_calibrationOverlay];
    [_calibrationOverlay setHidden:YES];
    
    if (ALWAYS_SHOW_EVERYTHING)
    {
        [_calibrationOverlay setHidden:NO];
        [_sensorBatteryIcon setHidden:NO];
        [_getStructureView setHidden:NO];
        [_structureMessageLabel setHidden:NO];
    }
    
    return self;
}

- (void)setSensorController:(STSensorController*)sensorController
{
    _sensorController = sensorController;
}

- (void)initBatteryIcon
{
    float width = 60;
    
    CGRect imageFrame = CGRectMake(1024 - (width + 20) , 0, width, 35);
    _sensorBatteryIcon = [[UIImageView alloc] initWithFrame: imageFrame];
    _sensorBatteryIcon.contentMode = UIViewContentModeScaleAspectFit;
    _sensorBatteryIcon.image = [UIImage imageNamed:@"SensorBattery"];
    _sensorBatteryIcon.clipsToBounds = YES;
    [_parentViewController.view addSubview:_sensorBatteryIcon];
    
    [_sensorBatteryIcon setHidden:YES];
}

- (void)startBatteryTimer
{
    // Create Battery Timers (First update, then 5s refresh):
    [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(updateBattery) userInfo:nil repeats:NO];
    if(_updateBatteryDisplayTimer)
    {
        [_updateBatteryDisplayTimer invalidate];
        _updateBatteryDisplayTimer = nil;
    }
    _updateBatteryDisplayTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(updateBattery) userInfo:nil repeats:YES];
}

- (void)initGetStructureView
{
    //local store for displaying structure connection message
    [LocalStoreHelper initialize];
    [[LocalStoreHelper globalInstance] loadLocalStore];
    if([[LocalStoreHelper globalInstance] objectForKey:@"hasStructureSensorConnected"] == nil)
    {
        [[LocalStoreHelper globalInstance] setValue:@"false" forKey:@"hasStructureSensorConnected"];
        [[LocalStoreHelper globalInstance] saveLocalStore];
    }
    _hasStructureSensorConnected = ([[[LocalStoreHelper globalInstance] objectForKey:@"hasStructureSensorConnected"] isEqualToString:@"true"]);
    
    CGRect frame = CGRectMake(NOTIFICATION_X, NOTIFICATION_Y, 340, 56);
    _getStructureView = [[UIView alloc] initWithFrame:frame];
    [StructureStatusUI applyUIStyle:_getStructureView];
    [_parentViewController.view addSubview:_getStructureView];
    _getStructureView.hidden = YES;
    
    UIImageView *structureImage = [[UIImageView alloc] initWithFrame:CGRectMake(0, 4, 120, 44)];
    structureImage.contentMode = UIViewContentModeCenter;
    structureImage.image = [UIImage imageNamed:@"GetStructure-for-Structure-App"];
    structureImage.clipsToBounds = YES;
    [_getStructureView addSubview:structureImage];
    
    UIButton *structureSensorReqdButton = [[UIButton alloc] initWithFrame:CGRectMake(116, 6, 220, 45)];
    const CGFloat fontSize = 17;
    
    NSDictionary *attrs = @{NSFontAttributeName: [UIFont fontWithName:@"OpenSans-Light" size:fontSize],
                           NSForegroundColorAttributeName: [UIColor whiteColor]};
    NSDictionary *subAttrs = @{NSFontAttributeName: [UIFont fontWithName:@"OpenSans-Light" size:fontSize],
                              NSForegroundColorAttributeName: [UIColor colorWithRed:0.160784314 green:0.670588235 blue:0.88627451 alpha:0.95]};
    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:@"Structure Sensor required."
                            attributes:attrs];
    [attributedText setAttributes:subAttrs range:NSMakeRange(0,16)];
    [structureSensorReqdButton setAttributedTitle:attributedText forState:UIControlStateNormal];
    [structureSensorReqdButton setAttributedTitle:attributedText forState:UIControlStateHighlighted];
    [_getStructureView addSubview:structureSensorReqdButton];
    [structureSensorReqdButton addTarget:self action:@selector(structureSensorButtonPressed:) forControlEvents: UIControlEventTouchUpInside];
}

- (void) structureSensorButtonPressed:(UIButton*) button
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://structure.io/get-a-sensor"]];
}

- (void)initStructureMessageLabel
{
    // Fully transparent message label, initially.
    CGRect frame = CGRectMake(0, 200, 1024, 36);
    _structureMessageLabel = [[UILabel alloc] initWithFrame:frame];
    _structureMessageLabel.textAlignment = NSTextAlignmentCenter;
    _structureMessageLabel.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.3];
    
    _structureMessageLabel.hidden = YES;
    [_parentViewController.view addSubview:_structureMessageLabel];
}

-(NSMutableAttributedString*) appMessageWithAttributedText:(NSString*)text range:(NSRange)range
{
    const CGFloat fontSize = 30;
    UIFont *lightFont = [UIFont fontWithName:@"OpenSans-Light" size:fontSize];
    UIFont *boldFont = [UIFont fontWithName:@"OpenSans-Semibold" size:fontSize];
    UIColor *foregroundColor = [UIColor whiteColor];
    
    // Create the attributes
    NSDictionary *attrs = @{NSFontAttributeName: lightFont,
                           NSForegroundColorAttributeName: foregroundColor};
    NSDictionary *subAttrs = @{NSFontAttributeName: boldFont,
                              NSForegroundColorAttributeName: foregroundColor};
    
    NSMutableAttributedString *attributedText =
    [[NSMutableAttributedString alloc] initWithString:text
                                           attributes:attrs];
    [attributedText setAttributes:subAttrs range:range];
    
    return attributedText;
}

- (void)showSensorStatusMessage:(NSMutableAttributedString*)attributedText
{
    [_structureMessageLabel setAttributedText:attributedText];
    
    //if we have no record of the sensor connecting, must display "get sensor" view
    if (!_hasStructureSensorConnected)
    {
        [_getStructureView setHidden:NO];
    }
    else
    {
        [_structureMessageLabel setHidden:NO animated:YES animationDuration:0.3];
    }
}

- (void) hideSensorStatusMessage
{
    //we interpret this message as meaning the sensor is properly connected.
    if (!_hasStructureSensorConnected)
    {
        _hasStructureSensorConnected = YES;
        [[LocalStoreHelper globalInstance] setValue:@"true" forKey:@"hasStructureSensorConnected"];
        [[LocalStoreHelper globalInstance] saveLocalStore];
        if (!ALWAYS_SHOW_EVERYTHING)
            [_getStructureView setHidden:YES];
    }
    
    if (!ALWAYS_SHOW_EVERYTHING)
        [_structureMessageLabel setHidden:YES animated:YES animationDuration:0.3];
}

# pragma mark - Structure delegate functions

- (void)gotSensorConnectionResult:(STSensorControllerInitStatus)result
{
    if (result == STSensorControllerInitStatusSuccess || result == STSensorControllerInitStatusAlreadyInitialized)
    {
        // We are connected, so get rid of potential previous messages being displayed.
        [self hideSensorStatusMessage];
        
        if( [_sensorController calibrationType] == STCalibrationTypeDeviceSpecific)
        {
            if (!ALWAYS_SHOW_EVERYTHING)
                [_calibrationOverlay setHidden:YES];
        }
        else
        {
            [_calibrationOverlay setHidden:NO];
        }
    }
    else
    {
        switch (result)
        {
            case STSensorControllerInitStatusSensorNotFound:
                NSLog(@"[Structure] no sensor found"); break;
            case STSensorControllerInitStatusOpenFailed:
                NSLog(@"[Structure] error: open failed."); break;
            case STSensorControllerInitStatusSensorIsWakingUp:
                NSLog(@"[Structure] error: sensor still waking up."); break;
            case STSensorControllerInitStatusAlreadyInitialized:
                NSLog(@"[Structure] error: already initialized."); break;
            default: {}
        }
        
        NSMutableAttributedString* attributedText = [self appMessageWithAttributedText:@"Please connect Structure Sensor." range:NSMakeRange(15,16)];
        [self showSensorStatusMessage:attributedText];
    }
}

- (void)sensorDidConnect
{
    NSLog(@"[Structure] Sensor connected!");
    
    [self startBatteryTimer];
}

- (void)sensorDidStopStreaming:(STSensorControllerDidStopStreamingReason) reason
{
    if (reason == STSensorControllerDidStopStreamingReasonAppWillResignActive)
        NSLog(@"[Structure] stopped streaming because of app backgrounding.");
    else
        NSLog(@"[Structure] stopped streaming for an unknown reason.");
    
    [_updateBatteryDisplayTimer invalidate];
    _updateBatteryDisplayTimer = nil;
}

- (void)sensorDidLeaveLowPowerMode
{
    NSMutableAttributedString* attributedText = [self appMessageWithAttributedText:@"Please connect Structure Sensor." range:NSMakeRange(15,16)];
    [self showSensorStatusMessage:attributedText];
}

- (void)sensorBatteryNeedsCharging
{
    // Notify the user that the sensor needs to be charged.
    NSMutableAttributedString* attributedText = [self appMessageWithAttributedText:@"Please charge Structure Sensor." range:NSMakeRange(14,16)];
    [self showSensorStatusMessage:attributedText];
}

- (void)sensorDidDisconnect
{
    NSLog(@"[Structure] Sensor disconnected!");
    
    NSMutableAttributedString* attributedText = [self appMessageWithAttributedText:@"Please connect Structure Sensor." range:NSMakeRange(15,16)];
    [self showSensorStatusMessage:attributedText];
    
    if (!ALWAYS_SHOW_EVERYTHING)
        [_calibrationOverlay setHidden:YES];
    
    [_updateBatteryDisplayTimer invalidate];
    _updateBatteryDisplayTimer = nil;
}

# pragma mark - update functions

- (void) updateBattery
{
    if (!_sensorController)
        return;
    
    if(![_sensorController isConnected]) {
        dNSLog(@"[Error] Why are we calling updateBattery if sensor is not connected?");
        return;
    }
    
    if(![_sensorController isLowPower]) // Low power is handled differently.
    {
        NSInteger percentage = [_sensorController getBatteryChargePercentage];
        [_sensorBatteryIcon setHidden: percentage > 5 ];
    }
}

@end
