/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <SceneKit/SceneKit.h>

@class GameData;

@interface DoorManager : NSObject
@property (nonatomic, retain) SCNNode *door1Collider;
@property (nonatomic, retain) SCNNode *door2Collider;
@property (nonatomic, retain) SCNNode *door3Collider;

-(id) initWithGameData:(GameData*)gameData;
-(void) physicsWorld:(SCNPhysicsWorld *)world didBeginContact:(SCNPhysicsContact *)contact;
-(void) openLoadingBayDoors;
-(void) closeLoadingBayDoors;
-(void) reset;
@end
