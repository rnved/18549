/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <SceneKit/SceneKit.h>

@class GameData;

@interface PointerNode : SCNNode

-(id) initWithGameData:(GameData*)gameData;
-(void) setTarget:(SCNNode*)target;
-(void) updatePointerNode;

@end
