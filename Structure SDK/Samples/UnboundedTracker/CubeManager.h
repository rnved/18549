/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <SceneKit/SceneKit.h>

@class GameData;

@interface CubeManager : NSObject

@property (nonatomic, retain) SCNNode* firstRoomCube;

-(id) initWithGameData:(GameData*)gameData;
-(void) dropFirstRoomCube;
-(void) physicsWorld:(SCNPhysicsWorld *)world didBeginContact:(SCNPhysicsContact *)contact;
-(void) reset;
-(void) dropSecondRoomCubes;
@end