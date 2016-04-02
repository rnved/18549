/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#pragma once

#import <Structure/StructureSLAM.h>

struct TrackerUpdate
{
    double timestamp = -1.0;
    GLKMatrix4 cameraPose = GLKMatrix4MakeScale(NAN, NAN, NAN);
    bool couldEstimatePose = false;
    NSError* trackingError = nil;
    STTrackerStatus trackerStatus = STTrackerStatusNotAvailable;
};

/**
 * We use a separate thread for the tracker to make sure we do not block the SceneKit
 * thread for too long, and do not keep the main thread too busy so it can still dispatch
 * events.
 */
@interface TrackerThread : NSObject
@property (nonatomic,readwrite) STTracker* tracker;
@property (nonatomic,readwrite) double threadPriority;
@property (nonatomic,readonly) TrackerUpdate lastUpdate;

-(void) start;
-(void) stop;
-(void) reset;

-(void) setInitialTrackerPose:(GLKMatrix4)newPose timestamp:(double)timestamp;
-(void) updateWithMotion:(CMDeviceMotion*)motion;
-(bool) updateWithDepthFrame:(STDepthFrame*)depthFrame colorFrame:(STColorFrame*)colorFrame maxWaitTimeSeconds:(double)waitTime;
-(TrackerUpdate) waitForUpdateMoreRecentThan:(NSTimeInterval)timestamp maxWaitTimeSeconds:(double)waitTime;
@end
