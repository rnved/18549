/*
 This file is part of the Structure SDK.
 Copyright © 2015 Occipital, Inc. All rights reserved.
 http://structure.io
 */

#import "ViewController.h"
#import "ViewController+OpenGL.h"

#import <Structure/Structure.h>
#import <Structure/StructureSLAM.h>

#pragma mark - Utilities

namespace // anonymous namespace for local functions
{
    float deltaRotationAngleBetweenPosesInDegrees (const GLKMatrix4& previousPose, const GLKMatrix4& newPose)
    {
        GLKMatrix4 deltaPose = GLKMatrix4Multiply(newPose,
                                                  // Transpose is equivalent to inverse since we will only use the rotation part.
                                                  GLKMatrix4Transpose(previousPose));
        
        // Get the rotation component of the delta pose
        GLKQuaternion deltaRotationAsQuaternion = GLKQuaternionMakeWithMatrix4(deltaPose);
        
        // Get the angle of the rotation
        const float angleInDegree = GLKQuaternionAngle(deltaRotationAsQuaternion)*180.f/M_PI;
        
        return angleInDegree;
    }
}

@implementation ViewController (SLAM)

#pragma mark - SLAM

// Setup SLAM related objects.
- (void)setupSLAM
{
    if (_slamState.initialized)
        return;
    
    // Initialize the scene.
    _slamState.scene = [[STScene alloc] initWithContext:_display.context
                                      freeGLTextureUnit:GL_TEXTURE2];
    
    // Initialize the camera pose tracker.
    NSDictionary* trackerOptions = @{
                                     kSTTrackerTypeKey: @(STTrackerDepthAndColorBased),
                                     kSTTrackerTrackAgainstModelKey: @FALSE, // Tracking against model works better in smaller scale scanning.
                                     kSTTrackerQualityKey: @(STTrackerQualityAccurate),
                                     };
    
    NSError* trackerInitError = nil;
    
    // Initialize the camera pose tracker.
    _slamState.tracker = [[STTracker alloc] initWithScene:_slamState.scene options:trackerOptions error:&trackerInitError];
    
    if (trackerInitError != nil)
    {
        NSLog(@"Error during STTracker init: %@", [trackerInitError localizedDescription]);
    }
    
    NSAssert (_slamState.tracker != nil, @"Could not create a tracker.");
    
    // Initialize the mapper.
    NSDictionary* mapperOptions =
    @{
      kSTMapperVolumeResolutionKey: @[@(_options.volumeResolution.x),
                                      @(_options.volumeResolution.y),
                                      @(_options.volumeResolution.z)]
      };
    
    _slamState.mapper = [[STMapper alloc] initWithScene:_slamState.scene
                                                options:mapperOptions];
    
    // We don't need a dense mesh during tracking, kSTTrackerTrackAgainstModelKey is false and
    // we will only render a wireframe view.
    _slamState.mapper.liveTriangleMeshEnabled = false;
    
    // We need a live wireframe mesh for our visualization. Keep it coarser for speed and aesthetic reasons.
    _slamState.mapper.liveWireframeMeshEnabled = true;
    _slamState.mapper.liveWireframeMeshSubsamplingFactor = 2;
    
    // Default volume size set in options struct
    _slamState.mapper.volumeSizeInMeters = _options.initialVolumeSizeInMeters;
    
    // Setup the camera placement initializer. We will set it to the center of the volume to
    // maximize the area of scan. The rotation will also be aligned to gravity.
    NSError* cameraPoseInitializerError = nil;
    _slamState.cameraPoseInitializer = [[STCameraPoseInitializer alloc]
                                        initWithVolumeSizeInMeters:_slamState.mapper.volumeSizeInMeters
                                        options:@{kSTCameraPoseInitializerStrategyKey:@(STCameraPoseInitializerStrategyGravityAlignedAtVolumeCenter)}
                                        error:&cameraPoseInitializerError];
    NSAssert (!cameraPoseInitializerError, @"Could not initialize STCameraPoseInitializer: %@", [cameraPoseInitializerError localizedDescription]);
    
    // Setup the initial volume size.
    [self adjustVolumeSize:_slamState.mapper.volumeSizeInMeters];
    
    // Start with cube placement mode
    [self enterPoseInitializationState];
    
    NSDictionary* keyframeManagerOptions = @{
                                             kSTKeyFrameManagerMaxSizeKey: @(_options.maxNumKeyframes),
                                             kSTKeyFrameManagerMaxDeltaTranslationKey: @(_options.maxKeyFrameTranslation),
                                             kSTKeyFrameManagerMaxDeltaRotationKey: @(_options.maxKeyFrameRotation),
                                             };
    
    NSError* keyFrameManagerInitError = nil;
    _slamState.keyFrameManager = [[STKeyFrameManager alloc] initWithOptions:keyframeManagerOptions error:&keyFrameManagerInitError];
    
    NSAssert (keyFrameManagerInitError == nil, @"Could not initialize STKeyFrameManger: %@", [keyFrameManagerInitError localizedDescription]);
    
    _slamState.initialized = true;
}

- (void)resetSLAM
{
    _slamState.prevFrameTimeStamp = -1.0;
    [_slamState.mapper reset];
    [_slamState.tracker reset];
    [_slamState.scene clear];
    [_slamState.keyFrameManager clear];
    
    _colorizedMesh = nil;
    _holeFilledMesh = nil;
}

- (void)clearSLAM
{
    _slamState.initialized = false;
    _slamState.scene = nil;
    _slamState.tracker = nil;
    _slamState.mapper = nil;
    _slamState.keyFrameManager = nil;
}

- (void)processDepthFrame:(STDepthFrame *)depthFrame
               colorFrame:(STColorFrame *)colorFrame
{
    // Upload the new color image for next rendering.
    if (colorFrame != nil)
        [self uploadGLColorTexture:colorFrame];
    
    switch (_slamState.roomCaptureState)
    {
        case RoomCaptureStatePoseInitialization:
        {
            // Estimate the new scanning volume position as soon as gravity has an estimate.
            if (GLKVector3Length(_lastCoreMotionGravity) > 1e-5f)
            {
                bool success = [_slamState.cameraPoseInitializer updateCameraPoseWithGravity:_lastCoreMotionGravity depthFrame:nil error:nil];
                NSAssert (success, @"Camera pose initializer error.");
            }
            
            break;
        }
            
        case RoomCaptureStateScanning:
        {
            GLKMatrix4 depthCameraPoseBeforeTracking = [_slamState.tracker lastFrameCameraPose];
            
            NSError* trackingError = nil;
            
            // Estimate the new camera pose.
            BOOL trackingOk = [_slamState.tracker updateCameraPoseWithDepthFrame:depthFrame colorFrame:colorFrame error:&trackingError];
            
            if (trackingOk)
            {
                // Integrate it to update the current mesh estimate.
                GLKMatrix4 depthCameraPoseAfterTracking = [_slamState.tracker lastFrameCameraPose];
                [_slamState.mapper integrateDepthFrame:depthFrame cameraPose:depthCameraPoseAfterTracking];
                
                // Make sure the pose is in color camera coordinates in case we are not using registered depth.
                GLKMatrix4 colorCameraPoseInDepthCoordinateSpace;
                [depthFrame colorCameraPoseInDepthCoordinateFrame:colorCameraPoseInDepthCoordinateSpace.m];
                GLKMatrix4 colorCameraPoseAfterTracking = GLKMatrix4Multiply(depthCameraPoseAfterTracking,
                                                                             colorCameraPoseInDepthCoordinateSpace);
                
                bool showHoldDeviceStill = false;
                
                // Check if the viewpoint has moved enough to add a new keyframe
                if ([_slamState.keyFrameManager wouldBeNewKeyframeWithColorCameraPose:colorCameraPoseAfterTracking])
                {
                    const bool isFirstFrame = (_slamState.prevFrameTimeStamp < 0.);
                    bool canAddKeyframe = false;
                    
                    if (isFirstFrame)
                    {
                        canAddKeyframe = true;
                    }
                    else
                    {
                        float deltaAngularSpeedInDegreesPerSeconds = FLT_MAX;
                        NSTimeInterval deltaSeconds = depthFrame.timestamp - _slamState.prevFrameTimeStamp;
                        
                        // If deltaSeconds is 2x longer than the frame duration of the active video device, do not use it either
                        CMTime frameDuration = self.videoDevice.activeVideoMaxFrameDuration;
                        if (deltaSeconds < (float)frameDuration.value/frameDuration.timescale*2.f)
                        {
                            // Compute angular speed
                            deltaAngularSpeedInDegreesPerSeconds = deltaRotationAngleBetweenPosesInDegrees (depthCameraPoseBeforeTracking, depthCameraPoseAfterTracking)/deltaSeconds;
                        }
                        
                        // If the camera moved too much since the last frame, we will likely end up
                        // with motion blur and rolling shutter, especially in case of rotation. This
                        // checks aims at not grabbing keyframes in that case.
                        if (deltaAngularSpeedInDegreesPerSeconds < _options.maxKeyframeRotationSpeedInDegreesPerSecond)
                        {
                            canAddKeyframe = true;
                        }
                    }
                    
                    if (canAddKeyframe)
                    {
                        [_slamState.keyFrameManager processKeyFrameCandidateWithColorCameraPose:colorCameraPoseAfterTracking
                                                                                     colorFrame:colorFrame
                                                                                     depthFrame:nil];
                    }
                    else
                    {
                        // Moving too fast. Hint the user to slow down to capture a keyframe
                        // without rolling shutter and motion blur.
                        if (_slamState.prevFrameTimeStamp > 0.) // only show the message if it's not the first frame.
                        {
                            showHoldDeviceStill = true;
                        }
                    }
                }
                
                // Compute the translation difference between the initial camera pose and the current one.
                GLKMatrix4 initialPose = _slamState.tracker.initialCameraPose;
                float deltaTranslation = GLKVector4Distance(GLKMatrix4GetColumn(depthCameraPoseAfterTracking, 3), GLKMatrix4GetColumn(initialPose, 3));
                
                // Show some messages if needed.
                if (showHoldDeviceStill)
                {
                    [self showTrackingMessage:@"Please hold still so we can capture a keyframe..."];
                }
                else if (deltaTranslation > _options.maxDistanceFromInitialPositionInMeters )
                {
                    // Warn the user if he's exploring too far away since this demo is optimized for a rotation around oneself.
                    [self showTrackingMessage:@"Please stay closer to the initial position."];
                }
                else
                {
                    [self hideTrackingErrorMessage];
                }
            }
            else if (trackingError.code == STErrorTrackerLostTrack)
            {
                [self showTrackingMessage:@"Tracker Lost!"];
            }
            else if (trackingError.code == STErrorTrackerPoorQuality)
            {
                switch ([_slamState.tracker status])
                {
                    case STTrackerStatusDodgyForUnknownReason:
                    {
                        NSLog(@"STTracker Tracker quality is bad, but we don't know why.");
                        break;
                    }
                        
                    case STTrackerStatusFastMotion:
                    {
                        NSLog(@"STTracker Camera moving too fast.");
                        // Don't show anything since this can happen often.
                        break;
                    }
                        
                    case STTrackerStatusTooClose:
                    {
                        NSLog(@"STTracker Too close to the model.");
                        [self showTrackingMessage:@"Too close to the scene! Please step back."];
                        break;
                    }
                        
                    case STTrackerStatusTooFar:
                    {
                        NSLog(@"STTracker Too far from the model.");
                        [self showTrackingMessage:@"Please get closer to the model."];
                        break;
                    }
                        
                    case STTrackerStatusRecovering:
                    {
                        NSLog(@"STTracker Recovering.");
                        [self showTrackingMessage:@"Recovering, please move gently."];
                        break;
                    }
                        
                    case STTrackerStatusModelLost:
                    {
                        NSLog(@"STTracker model not in view.");
                        [self showTrackingMessage:@"Please put the model back in view."];
                        break;
                    }
                    default:
                        NSLog(@"STTracker unknown quality.");
                }
            }
            else
            {
                [self showTrackingMessage:[NSString stringWithFormat:@"Tracker error: %@", [trackingError localizedDescription]]];
                NSLog(@"[Structure] STTracker Error: %@.", [trackingError localizedDescription]);
            }
            
            _slamState.prevFrameTimeStamp = depthFrame.timestamp;
            
            break;
        }
            
        case RoomCaptureStateViewing:
        default:
        {} // do nothing, the MeshViewController will take care of this.
    }
}

@end
