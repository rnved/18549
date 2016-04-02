/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController+SLAM.h"
#import "ViewController+Camera.h"
#import "ViewController+Sensor.h"

#import <mach/mach_time.h>

#import "MotionLogs.h"

// Helper functions
namespace
{
    double nowInSeconds()
    {
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        
        uint64_t newTime = mach_absolute_time();
        
        return ((double)newTime*timebase.numer)/((double)timebase.denom *1e9);
    }
}

@implementation ViewController (SLAM)

- (void)clearSLAM
{
    _slamState.initialized = false;
    _slamState.scene = nil;
    [_slamState.trackerThread reset];
    [_slamState.trackerThread stop];
    _slamState.trackerThread.tracker = nil;
}

// Setup SLAM related objects.
- (void)setupSLAM
{
    if (_slamState.initialized)
        return;
    
    // Create an EAGLContext to use with the tracker.
    _slamState.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!_slamState.context)
    {
        NSLog(@"Failed to create ES context");
        return;
    }
    
    // Initialize the scene.
    _slamState.scene = [[STScene alloc] initWithContext:_slamState.context
                                      freeGLTextureUnit:GL_TEXTURE2];
    
    NSDictionary* trackerOptions = @{
                                     kSTTrackerTypeKey: @(STTrackerDepthAndColorBased),
                                     kSTTrackerTrackAgainstModelKey: @FALSE, // not creating a global model
                                     kSTTrackerQualityKey: @(STTrackerQualityAccurate),
                                     kSTTrackerBackgroundProcessingEnabledKey: @YES,
                                     kSTTrackerAvoidPitchRollDriftKey: @YES,
                                     kSTTrackerAvoidHeightDriftKey: @YES,
                                     };
    
    NSError* trackerInitError = nil;
    STTracker* tracker = [[STTracker alloc] initWithScene:_slamState.scene options:trackerOptions error:&trackerInitError];
    NSAssert (tracker != nil, @"Could not create a tracker.");
    
    if (!tracker)
    {
        NSLog(@"Could not create tracker: %@", [trackerInitError localizedDescription]);
        
        NSString *alertTitle = @"Fatal Error";
        NSString *alertText = @"Could not create a tracker.";
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:alertTitle
                                                                       message:alertText
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:alert animated:YES completion:nil];
    }
    
    _slamState.trackerThread = [[TrackerThread alloc] init];
    _slamState.trackerThread.tracker = tracker;
    [_slamState.trackerThread start];
    
    // Setup the cube placement initializer.
    _slamState.cameraPoseInitializer = [[STCameraPoseInitializer alloc]
                                        initWithVolumeSizeInMeters:GLKVector3Make(1.f,1.f,1.f) // not used
                                        options:@{kSTCameraPoseInitializerStrategyKey: @(STCameraPoseInitializerStrategyGravityAlignedAtOrigin)}
                                        error:nil];
    
    // Start with cube placement mode
    [self enterWaitingForStartState];
    
    _slamState.initialized = true;
}

// This will be called after resuming from background or if the sensor was unplugged. We want
// to reset the tracker because it won't be able to recover, but to keep the same pose in the
// virtual world.
- (void)gracefullyResetTrackerWhileKeepingPreviousPose
{
    TrackerUpdate lastUpdate = _slamState.trackerThread.lastUpdate;
    
    if (lastUpdate.couldEstimatePose)
    {
        [_slamState.trackerThread reset];
        [_slamState.trackerThread setInitialTrackerPose:lastUpdate.cameraPose timestamp:nowInSeconds()];
    }
    else
    {
        NSLog(@"Warning: could not reset the pose gracefully, there was no previous estimate.");
    }
}

- (void)enterWaitingForStartState
{
    // Cannot be lost in initial placement mode.
    self.trackingLostLabel.hidden = YES;
    
    _slamState.isTracking = NO;
    
    // Restore automatic color camera parameters.
    [self lockColorCameraExposure:false andLockWhiteBalance:false andLockFocus:true];
}

- (void)enterTrackingState
{
    _slamState.shouldResetPose = YES;
    
    // Lock color camera settings to ensure smoother transitions between keyframes.
    [self lockColorCameraExposure:true andLockWhiteBalance:true andLockFocus:true];
    
    _slamState.isTracking = YES;
}

- (TrackerUpdate)getMoreRecentTrackerUpdate:(double)previousTimestamp
{
    TrackerUpdate newTrackerUpdate;
    
    // If the sensor is disconnected, we don't want the panning to slow down.
    // Never wait for more than 25 ms. We probably dropped a frame if this happens.
    int maxWaitTime = [self isStructureConnectedAndCharged] ? 0.025: 0.0166;
    newTrackerUpdate = [_slamState.trackerThread waitForUpdateMoreRecentThan:previousTimestamp maxWaitTimeSeconds:maxWaitTime];

    // Motion Logging
    if (newTrackerUpdate.couldEstimatePose &&
        newTrackerUpdate.trackingError == nil &&
        newTrackerUpdate.trackerStatus != STTrackerStatusNotAvailable)
    {
        [MotionLogs logTrackerPose:newTrackerUpdate.cameraPose atTime:newTrackerUpdate.timestamp];
    }
    
    return newTrackerUpdate;
}

#pragma mark - Structure Sensor & SLAM Management

- (void)onStructureSensorStartedStreaming
{
    [self clearSLAM];
    
    // We cannot initialize SLAM objects before a sensor is ready to be used, so now is a good time
    // to do it.
    if (!_slamState.initialized)
    {
        // One-time setup of SLAM related members now that we have a sensor connected
        [self setupSLAM];
    }
    else
    {
        // Here we need to reset the tracker because the user may have moved far away, and
        // exposure might be different too.
        [self gracefullyResetTrackerWhileKeepingPreviousPose];
    }
}

- (void)sensorDidOutputSynchronizedDepthFrame:(STDepthFrame *)depthFrame
                                andColorFrame:(STColorFrame *)colorFrame
{
    if (_slamState.initialized)
    {
        if (!_slamState.isTracking) // Initially, we are in the waiting state.
        {
            // Estimate the new initial position. The cameraPoseInitializer will make sure the initial
            // orientation is aligned with gravity.
            [_slamState.cameraPoseInitializer updateCameraPoseWithGravity:_lastGravity depthFrame:nil error:nil];
            
            // Starting tracking right away.
            [self enterTrackingState];
        }
        else
        {
            if (_slamState.shouldResetPose)
            {
                _slamState.shouldResetPose = NO;
                
                if (!_slamState.cameraPoseInitializer.hasValidPose)
                {
                    NSLog(@"Something is wrong, we don't have a pose from the cube initializer.");
                }
                else
                {
                    GLKMatrix4 initialCameraPose = _slamState.cameraPoseInitializer.cameraPose;
                    
                    // Set the initial camera translation to human height (1.5m). GLKMatrix4 is column-major.
                    initialCameraPose = GLKMatrix4SetColumn (initialCameraPose, 3, _slamState.initialTrackerTranslation);
                    
                    [_slamState.trackerThread setInitialTrackerPose:initialCameraPose timestamp:depthFrame.timestamp];
                }
            }
            else
            {
                double newTimestamp = nowInSeconds();
                // This test is trying to avoid processing frames which arrive in batch. Sometimes scheduling becomes messy
                // and instead of getting a frame after 33ms, we get no frames for 66ms, and then two frames at the same time.
                // Trying to process them both will make the SceneKit thread starve, so we'll just skip one if we receive two
                // frames in less than 5 milliseconds.
                if (_slamState.previousFrameTimestamp < 0 || (newTimestamp - _slamState.previousFrameTimestamp) > 0.005)
                {
                    const int timeoutSeconds = 20/1000.; // don't allow it to eat more than 20ms of the main thread.

                    // We need to take a copy of the depth frame since it won't survive the callback scope.
                    // However the color frame will live long enough since the AVFoundation pool is quite big.
                    [_slamState.trackerThread updateWithDepthFrame:[depthFrame copy] colorFrame:colorFrame maxWaitTimeSeconds:timeoutSeconds];
                }
                _slamState.previousFrameTimestamp = newTimestamp;
            }
        }
    }
}

@end
