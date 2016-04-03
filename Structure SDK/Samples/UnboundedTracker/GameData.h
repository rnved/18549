/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <SceneKit/SceneKit.h>

#import "AudioManager.h"

#import "Player.h"
#import "CubeManager.h"
#import "DoorManager.h"
#import "ButtonManager.h"
#import "PointerNode.h"

// Class holding the various game objects
@interface GameData : NSObject

// The SCNView contains scene and rootNode
@property (nonatomic, retain) SCNView* view;

@property (nonatomic, retain) Player* player;

@property (nonatomic, retain) NSMutableArray *grabbableObjects;
@property (nonatomic, retain) NSMutableArray *raycastIgnoredObjects;

@property (nonatomic, retain) CubeManager* cubeManager;
@property (nonatomic, retain) DoorManager *doorManager;
@property (nonatomic, retain) ButtonManager *buttonManager;
@property (nonatomic, retain) PointerNode *pointerNode;

@end
