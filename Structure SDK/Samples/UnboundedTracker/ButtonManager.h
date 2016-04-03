/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <SceneKit/SceneKit.h>

@class GameData;

@interface ButtonManager : NSObject

@property (nonatomic, retain) SCNNode *redButton;
@property (nonatomic, retain) SCNNode *blueButton;
@property (nonatomic, retain) SCNNode *blueButtonBase;
@property (nonatomic, retain) SCNNode *blueButtonHatch;

-(id) initWithGameData:(GameData*)gameData;

-(void) physicsWorld:(SCNPhysicsWorld *)world
     didBeginContact:(SCNPhysicsContact *)contact
    isGrabbingObject:(BOOL)isGrabbingObject;

-(void) physicsWorld:(SCNPhysicsWorld *)world didEndContact:(SCNPhysicsContact *)contact;
-(bool) getRedButtonPressed;
-(bool) getBlueButtonPressed;
-(void) setBlueButtonPressed:(bool)pressed;
-(void) updateButtons:(float)time;
-(void) blinkRedButton;
-(void) reset;
@end
