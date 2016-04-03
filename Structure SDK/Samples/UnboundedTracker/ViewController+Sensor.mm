/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController+Sensor.h"
#import "ViewController+IMU.h"
#import "ViewController+SLAM.h"
#import "MotionLogs.h"

@implementation ViewController (Sensor)

#pragma mark - setup

- (void)setupStructureSensor
{
    if (_sensorController)
        return;
    
    // Setup Structure Sensor
    _sensorController = [STSensorController sharedController];
    // Set ourself as the delegate.
    __weak ViewController *weakSelf = self;
    _sensorController.delegate = weakSelf;
    
    [_structureStatusUI setSensorController:_sensorController];
}

- (STSensorControllerInitStatus)connectToStructureAndStartStreaming
{
    if (!_sensorController)
        return STSensorControllerInitStatusSensorNotFound;
    
    // Try connecting to a Structure Sensor.
    STSensorControllerInitStatus result = [_sensorController initializeSensorConnection];
    
    [_structureStatusUI gotSensorConnectionResult:result];
    
    if (result == STSensorControllerInitStatusSuccess || result == STSensorControllerInitStatusAlreadyInitialized)
        [self startStructureStreaming];
    
    return result;
}

- (void)startStructureStreaming
{
    if (![self isStructureConnectedAndCharged])
        return;
    
    // Tell the driver to start streaming.
    [_sensorController startStreamingWithOptions:@{kSTStreamConfigKey : @(_slamState.structureStreamConfig),
                                                   kSTFrameSyncConfigKey : @(STFrameSyncDepthAndRgb)} error:nil];
    
    NSLog(@"[Structure] streaming started");
    
    // Notify and initialize streaming dependent objects.
    [self onStructureSensorStartedStreaming];
    
    [[self recordButton] setHidden:NO];
    [[self recordButton] setTitle:@"Record Path" forState:UIControlStateNormal];
}

- (BOOL)isStructureConnectedAndCharged
{
    return [_sensorController isConnected] && ![_sensorController isLowPower];
}

#pragma mark - Structure delegate events

- (void)sensorDidConnect
{
    [_structureStatusUI sensorDidConnect];
    
    [self connectToStructureAndStartStreaming];
}

- (void)sensorDidLeaveLowPowerMode
{
    [_structureStatusUI sensorDidLeaveLowPowerMode];
    
    [[self recordButton] setHidden:NO];
}

- (void)sensorBatteryNeedsCharging
{
    [_structureStatusUI sensorBatteryNeedsCharging];
    
    [[self recordButton] setHidden:YES];
    [MotionLogs stopMotionLogRecording];
}

- (void)sensorDidStopStreaming:(STSensorControllerDidStopStreamingReason) reason
{
    [_structureStatusUI sensorDidStopStreaming:reason];
    
    [[self recordButton] setHidden:YES];
    [MotionLogs stopMotionLogRecording];
}

- (void)sensorDidDisconnect
{
    [_structureStatusUI sensorDidDisconnect];
    
    [[self recordButton] setHidden:YES];
    [MotionLogs stopMotionLogRecording];
}

@end
