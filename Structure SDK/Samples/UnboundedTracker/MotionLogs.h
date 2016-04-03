/*
 This file is part of the Structure SDK.
 Copyright © 2015 Occipital, Inc. All rights reserved.
 http://structure.io
 */

#import <SceneKit/SceneKit.h>
#import <GLKit/GLKit.h>

/**
MotionLogs demonstrates how to record and export tracker motion.
There are two types of tracker motion we may be interested in:
- Motion of the camera relative to the game world
- Motion of the tracker relative to the real world

Game motion is out-of-sync from real world motion because of movements in the game world that aren't reflected in the real world, e.g:
  - panning & warping
  - running into (game) walls
  - we exaggerate horizontal motion 2.5x relative to vertical motion
  
We output game camera motion as a basic csv format, to [DATE]GameCameraPoses.log. These will be loaded on startup for replay.
  
We output tracker motion in the .dae format, to [DATE]WorldCameraPoses.dae. This can be loaded in an external 3D editor such as MODO or Maya as a camera path. 
 
Both Motion logs are accessible from iTunes Files Sharing.
*/
@interface MotionLogs : NSObject
+ (void) loadLogsWithRootNode:(SCNNode*)rootNode andPlayButton:(UIButton*)playMotionLogsButton;

+ (int) getLogCount;
+ (BOOL) isPlaying;

+ (void) beginAtTime:(NSTimeInterval)startTime;
+ (void) updateAtTime:(NSTimeInterval)time;
+ (void) resetPlayback;

+ (void) logGameCameraPose:(SCNMatrix4)povTransform atTime:(double)timestamp;
+ (void) logTrackerPose:(GLKMatrix4)povTransform atTime:(double)timestamp;

+ (void) startMotionLogRecording;
+ (void) stopMotionLogRecording;
+ (BOOL) isRecording;
@end
