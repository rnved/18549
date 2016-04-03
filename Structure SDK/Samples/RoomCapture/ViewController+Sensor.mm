/*
 This file is part of the Structure SDK.
 Copyright © 2015 Occipital, Inc. All rights reserved.
 http://structure.io
 */

#import "ViewController.h"
#import "ViewController+Camera.h"
#import "ViewController+Sensor.h"
#import "ViewController+SLAM.h"
#import "ViewController+OpenGL.h"

#import <Structure/Structure.h>
#import <Structure/StructureSLAM.h>

@implementation ViewController (Sensor)

#pragma mark -  Structure Sensor delegates

- (void)setupStructureSensor
{
    // Get the sensor controller singleton.
    _sensorController = [STSensorController sharedController];
    
    // Set ourself as the delegate to receive sensor data.
    _sensorController.delegate = self;
}

- (BOOL)isStructureConnectedAndCharged
{
    return [_sensorController isConnected] && ![_sensorController isLowPower];
}

- (void)sensorDidConnect
{
    NSLog(@"[Structure] Sensor connected!");
    
    if ([self currentStateNeedsSensor])
        [self connectToStructureSensorAndStartStreaming];
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
    if (reason == STSensorControllerDidStopStreamingReasonAppWillResignActive)
    {
        [self stopColorCamera];
        NSLog(@"[Structure] Stopped streaming because the app will resign its active state.");
    }
    else
    {
        NSLog(@"[Structure] Stopped streaming for an unknown reason.");
    }
}

- (void)sensorDidDisconnect
{
    // If we receive the message while in background, do nothing. We'll check the status when we
    // become active again.
    if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive)
        return;
    
    // Reset the scan on disconnect, since we won't be able to recover afterwards.
    if (_slamState.roomCaptureState == RoomCaptureStateScanning)
    {
        [self resetButtonPressed:self];
    }
    
    [self stopColorCamera];
    
    NSLog(@"[Structure] Sensor disconnected!");
    // We only show the app status when we need sensor
    if ([self currentStateNeedsSensor])
    {
        _appStatus.sensorStatus = AppStatus::SensorStatusNeedsUserToConnect;
        [self updateAppStatusMessage];
    }
    
    if (_calibrationOverlay)
        _calibrationOverlay.hidden = true;
    
    [self updateIdleTimer];
}

- (STSensorControllerInitStatus)connectToStructureSensorAndStartStreaming
{
    
    // Try connecting to a Structure Sensor.
    STSensorControllerInitStatus result = [_sensorController initializeSensorConnection];
    
    if (result == STSensorControllerInitStatusSuccess || result == STSensorControllerInitStatusAlreadyInitialized)
    {
        // We are connected, so get rid of potential previous messages being displayed.
        _appStatus.sensorStatus = AppStatus::SensorStatusOk;
        [self updateAppStatusMessage];
        
        // Start streaming depth data.
        [self startStructureSensorStreaming];
    }
    else
    {
        switch (result)
        {
            case STSensorControllerInitStatusSensorNotFound:     NSLog(@"[Structure] No sensor found."); break;
            case STSensorControllerInitStatusOpenFailed:         NSLog(@"[Structure] Error: open failed."); break;
            case STSensorControllerInitStatusSensorIsWakingUp:   NSLog(@"[Structure] Sensor is waking up."); break;
            default: {}
        }
        
        _appStatus.sensorStatus = AppStatus::SensorStatusNeedsUserToConnect;
        [self updateAppStatusMessage];
    }
    
    [self updateIdleTimer];
    
    return result;
}

- (void)startStructureSensorStreaming
{
    if (![self isStructureConnectedAndCharged])
    {
        NSLog(@"Error: Structure Sensor not connected or not charged.");
        return;
    }
    
    // Tell the driver to start streaming.
    // We are also using the color camera, so make sure the depth gets synchronized with it.
    NSError *error = nil;
    BOOL optionsAreValid = [_sensorController startStreamingWithOptions:@{
                                                                          kSTStreamConfigKey : @(_options.structureStreamConfig),
                                                                          kSTFrameSyncConfigKey : @(STFrameSyncDepthAndRgb),
                                                                          kSTColorCameraFixedLensPositionKey: @(_options.colorCameraLensPosition)
                                                                          }
                                                                  error:nil];
    
    if (!optionsAreValid)
    {
        NSLog(@"Error during streaming start: %s", [[error localizedDescription] UTF8String]);
        return;
    }
    
    NSLog(@"[Structure] Streaming started.");
    
    
    // We'll only turn on the color camera if we have at least an approximate calibration
    STCalibrationType calibrationType = [_sensorController calibrationType];
    if(calibrationType == STCalibrationTypeApproximate || calibrationType == STCalibrationTypeDeviceSpecific)
    {
        _appStatus.colorCameraIsCalibrated = true;
        [self updateAppStatusMessage];
        
        [self startColorCamera];
        
    }
    else
    {
        NSLog(@"This device does not have a calibration between color and depth.");
        
        _appStatus.colorCameraIsCalibrated = false;
        [self updateAppStatusMessage];
    }
    
    
    // Notify and initialize streaming dependent objects.
    [self onStructureSensorStartedStreaming];
}

- (void)onStructureSensorStartedStreaming
{
    STCalibrationType calibrationType = [_sensorController calibrationType];
    
    // The Calibrator app will be updated to support future iPads, and additional attachment brackets will be released as well.
    const bool deviceIsLikelySupportedByCalibratorApp = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
    
    // Only present the option to switch over to the Calibrator app if the sensor doesn't already have a device specific
    // calibration and the app knows how to calibrate this iOS device.
    if (calibrationType != STCalibrationTypeDeviceSpecific && deviceIsLikelySupportedByCalibratorApp)
    {
        if (_calibrationOverlay)
            _calibrationOverlay.hidden = false;
        else
            _calibrationOverlay = [CalibrationOverlay calibrationOverlaySubviewOf:self.view atOrigin:CGPointMake(16, 16)];
    }
    else
    {
        if (_calibrationOverlay)
            _calibrationOverlay.hidden = true;
    }
}

- (void)sensorDidOutputSynchronizedDepthFrame:(STDepthFrame *)depthFrame
                                andColorFrame:(STColorFrame*)colorFrame
{
    if (_slamState.initialized)
    {
        [self processDepthFrame:depthFrame colorFrame:colorFrame];
        // Scene rendering is triggered by new frames to avoid rendering the same view several times.
        [self renderSceneWithDepthFrame:depthFrame colorFrame:colorFrame];
    }
}

@end
