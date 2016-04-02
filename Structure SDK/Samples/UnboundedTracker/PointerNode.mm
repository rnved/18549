/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "PointerNode.h"
#import "SCNTools.h"

#import "GameData.h"

@interface PointerNode ()
{
    GameData* _gameData;
    
    SCNNode *_pointerNode;
    SCNNode *_mainTransform;
    SCNNode *_target;
}
@end

@implementation PointerNode

-(id) initWithGameData:(GameData*)gameData
{
    self = [super init];
    
    if (self)
    {
        _gameData = gameData;
        
        SCNScene *pointerScene = [SCNScene sceneNamed:@"models.scnassets/Pointer.dae"];
        _pointerNode = [pointerScene.rootNode childNodeWithName:@"PointerMesh" recursively:NO];
        [_pointerNode setRotation:SCNVector4Make(0, 1, 0, -90*(M_PI/180))];
        
        _mainTransform = [SCNNode node];
        [self addChildNode:_mainTransform];
        [_mainTransform addChildNode:_pointerNode];
        
        [_gameData.view.scene.rootNode addChildNode:self];
        
        [_gameData.raycastIgnoredObjects addObject:_pointerNode];
        
        [self setTarget:nil];
    }
    return self;
}

-(void) setTarget:(SCNNode*)node
{
    if(node == nil)
    {
        _pointerNode.hidden = YES;
        _target = nil;
        if([[_mainTransform constraints] count]>0)
        {
            [_mainTransform setConstraints:nil];
        }
    }
    else
    {
        _pointerNode.hidden = NO;
        _target = node;
        SCNLookAtConstraint *constraint = [SCNLookAtConstraint lookAtConstraintWithTarget:node];
        [constraint setGimbalLockEnabled:YES];
        [_mainTransform setConstraints:@[constraint]];
    }
    
}

-(void) updatePointerNode
{
    if(_target == nil)
        return;

    SCNVector3 offsetVector = [SCNTools getLookAtVectorOfNode:_gameData.player.pov];
    offsetVector.y -= 0.4;
    float offsetVectorFactor = 0.3;
    offsetVector = [SCNTools multiplyVector:offsetVector byFloat:offsetVectorFactor];
    SCNVector3 pointerPos = [SCNTools addVector:[SCNTools getWorldPos:_gameData.player.pov] toVector:offsetVector];
    pointerPos.y = pointerPos.y < 0.3 ? 0.3 : pointerPos.y;
    [self setPosition:pointerPos];
    float scale = 0.3;
    [_pointerNode setScale:SCNVector3Make(scale, scale, scale)];
}

@end
