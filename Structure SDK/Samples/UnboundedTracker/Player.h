/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <UIKit/UIKit.h>
#import <SceneKit/SceneKit.h>

#import "TrackerThread.h"
#import "Reticle.h"

@class GameData;

@interface Player : NSObject

@property Reticle *reticle;

@property (nonatomic, retain) SCNNode *playerNode;
@property (nonatomic, retain) SCNNode *capsule;
@property (nonatomic, retain) SCNNode *playerPanNode;
@property (nonatomic, retain) SCNNode *panRotationNode;
@property (nonatomic, retain) SCNNode *heightNode;
@property (nonatomic, retain) SCNNode *pov;

@property (nonatomic, retain) SCNNode *grabReference;
@property (nonatomic, retain) SCNNode *raycastPointer;
@property (nonatomic, retain) SCNNode *attachedObject;
@property (nonatomic, retain) SCNNode *pointAtObject;
@property float pointAtDistance;

@property (nonatomic, retain) SCNNode *warpPoint;

@property SCNVector3 translationScaleFactor;

@property float movementFinishTime;
@property BOOL allowMovement;

@property (nonatomic, readonly) bool canGrab;
@property (nonatomic, readonly) bool canWarp;
@property (nonatomic, readonly) bool warpButtonHasBeenPressed;

@property float startRoom;

@property (nonatomic, retain) UIButton *warpButton;
@property (nonatomic, retain) UIButton *actionButton;

-(id) initWithGameData:(GameData*)gameData;

-(void) reset;
-(void) jumpToLab;
-(void) actionButtonDown;
-(void) actionButtonUp;
-(void) warpButtonDown;
-(void) warpButtonUp;

// Update the status of sceneKit after UI has been processed
-(void) updateUI;

// Update the player's position from new tracker pose.
-(void) updateWithTrackerPose:(const TrackerUpdate&) trackerUpdate locked:(BOOL)isLocked deltaTime:(float)time;

// Happens after player is updated with pose.
-(void) updateSceneKit;

-(void) setWarpEnabled:(BOOL)warpEnabled;
@end
