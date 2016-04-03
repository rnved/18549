/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "CubeManager.h"
#import "SCNTools.h"

#import "GameData.h"

@interface CubeManager ()
{
    GameData* _gameData;
    
    // The node that holds the first room cube in the air to drop from.
    SCNNode *_firstRoomParent;
    
    // The nodes that hold the cubes up in the air to drop them.
    NSMutableArray *_secondRoomParents;
    
    // The second room cubes
    NSMutableArray *_secondRoomCubes;
    
    // The first room cube
    NSMutableArray *_allCubes;
    
    // Limit how often particles are played
    int _collisions;
}
@end

@implementation CubeManager

const SCNVector3 firstRoomCubeStartPosition = SCNVector3Make(0, 7.4, 0);

-(id) initWithGameData:(GameData*)gameData
{
    self = [super init];
    if (self)
    {
        _gameData = gameData;
        
        [self createFirstRoomCube];
        [self createSecondRoomCubes];
        _collisions = 0;
    }
    
    return self;
}

-(SCNNode*) createFirstRoomCube
{
    _firstRoomParent = [[SCNNode alloc] init];
    
    [_gameData.view.scene.rootNode addChildNode:_firstRoomParent];
    [_firstRoomParent setPosition:firstRoomCubeStartPosition];
    
    // First room cube
    const float BOX_SIDE_LENGTH = 0.735;
    SCNNode *cube = [self getCubeResource];
    cube.name = [NSString stringWithFormat:@"FirstRoom_Cube"];
    SCNGeometry *cubeGeo =[SCNBox boxWithWidth:BOX_SIDE_LENGTH height:BOX_SIDE_LENGTH length:BOX_SIDE_LENGTH chamferRadius:0];
    SCNPhysicsShape *blockShape = [SCNPhysicsShape shapeWithGeometry:cubeGeo options:nil];
    
    // Start the cube as dynamic, if it's started as kinematic then it never gets
    // its gravity set and will float when parented to the root node.
    [cube setPhysicsBody:[SCNPhysicsBody bodyWithType:SCNPhysicsBodyTypeDynamic shape:blockShape]];
    [cube.physicsBody setContactTestBitMask:SCNPhysicsCollisionCategoryAll];
    [_firstRoomParent addChildNode:cube];
    
    _allCubes = [[NSMutableArray alloc] init];
    [_allCubes addObject:cube];
    
    // Change to kinematic after added to rootnode if you don't do this then scenekit will forget
    // that objects can change between dynamic and kinematic.
    [cube.physicsBody setType:SCNPhysicsBodyTypeKinematic];
    [cube setPosition:SCNVector3Zero];
    
    [self setFirstRoomCube:cube];
    [_gameData.grabbableObjects addObject:self.firstRoomCube];
    
    return cube;
}

-(NSMutableArray*) createSecondRoomCubes
{
    _secondRoomCubes = [[NSMutableArray alloc] init];
    for (int i = 0; i < 10; ++i)
    {
        SCNNode *secondRoomParent = [[SCNNode alloc] init];
        [_secondRoomParents addObject:secondRoomParent];
        [_gameData.view.scene.rootNode addChildNode:secondRoomParent];
        [secondRoomParent setPosition:SCNVector3Make(-35, 10, -5 + i)];
        
        // For whatever reason the automatic physics body assignment is big and the cube will float
        const float BOX_SIDE_LENGTH = 0.735;
        SCNNode *cube = [self getCubeResource];
        cube.name = [NSString stringWithFormat:@"SecondRoom_Cube%i", i];
        SCNGeometry *cubeGeo =[SCNBox boxWithWidth:BOX_SIDE_LENGTH height:BOX_SIDE_LENGTH length:BOX_SIDE_LENGTH chamferRadius:0];
        SCNPhysicsShape *blockShape = [SCNPhysicsShape shapeWithGeometry:cubeGeo options:nil];
        
        // Start cube as dynamic
        [cube setPhysicsBody:[SCNPhysicsBody bodyWithType:SCNPhysicsBodyTypeDynamic shape:blockShape]];
        
        [cube.physicsBody setContactTestBitMask:SCNPhysicsCollisionCategoryAll];
        
        // Change to kinematic after added to rootnode if you don't do this then scenekit will
        // forget that objects can change between dynamic and kinematic
        [cube.physicsBody setType:SCNPhysicsBodyTypeKinematic];
        [secondRoomParent addChildNode:cube];
        [_allCubes addObject:cube];
        [cube setPosition:SCNVector3Zero];
        
        [_secondRoomCubes addObject:cube];
    }
    [_gameData.grabbableObjects addObjectsFromArray:_secondRoomCubes];
    
    return _secondRoomCubes;
}


// Load the dae scene file for the cube
-(SCNNode*) getCubeResource
{
    static SCNNode *cubeNodeSource;
    
    if (cubeNodeSource == nil)
    {
        SCNScene *cubeScene = [SCNScene sceneNamed:@"models.scnassets/HappyBox.dae"];
        cubeNodeSource = [cubeScene.rootNode childNodeWithName:@"HappyBox" recursively:YES];
    }
    
    return [cubeNodeSource copy];
}

// Button Manager calls this when the red button is pressed just changes to dynamic to make it fall
-(void) dropFirstRoomCube
{
    [SCNTransaction begin];
    {
        [self.firstRoomCube.physicsBody setType:SCNPhysicsBodyTypeDynamic];
        [_gameData.view.scene.rootNode addChildNode:self.firstRoomCube];
        [self.firstRoomCube setPosition:firstRoomCubeStartPosition];
    }
    [SCNTransaction commit];
}


// Drops second room cube when the door manager tells it to
-(void) dropSecondRoomCubes
{
    for(int i = 0; i < _secondRoomCubes.count; ++i)
    {
        SCNNode *cube = _secondRoomCubes[i];
        [SCNTransaction begin];
        {
            [cube.physicsBody setType:SCNPhysicsBodyTypeDynamic];
            [_gameData.view.scene.rootNode addChildNode:cube];
            [cube setPosition:SCNVector3Make(-35, 10 + sin(i * 1.2), -5 + i)];
        }
        [SCNTransaction commit];
    }
}

-(void) physicsWorld:(SCNPhysicsWorld *)world didBeginContact:(SCNPhysicsContact *)contact
{
    SCNNode* nodeA = contact.nodeA;
    SCNNode* nodeB = contact.nodeB;
    bool isACube = [_allCubes containsObject:nodeA];
    bool isBCube = [_allCubes containsObject:nodeB];
    
    if(isACube || isBCube)
    {
        // Mitigate how often bonks happen, it gets annoying when it happens every time.
        _collisions++;
        
        // One of the nodes is a cube.
        SCNVector3 impactA = contact.nodeA.physicsBody.velocity;
        SCNVector3 impactB = contact.nodeB.physicsBody.velocity;
        float impactAMagnitude = [SCNTools vectorMagnitude:impactA];
        float impactBMangitude = [SCNTools vectorMagnitude:impactB];
        
        if((_collisions%10 == 0) && ((impactAMagnitude > 1.0) || (impactBMangitude > 1.0)))
        {
            [self playParticleEffectAtPosition:contact.contactPoint named:@"Cube_Impact"];
        }
    }
}

// Create and kill a particle system at the point of impact
-(void) playParticleEffectAtPosition:(SCNVector3)position named:(NSString*)name
{
    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration : 1.0];
    [SCNTransaction setAnimationTimingFunction : [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault]];
    {
        SCNNode *impactNode = [SCNNode node];
        impactNode.position = position;
        SCNParticleSystem *hitEffect = [SCNParticleSystem particleSystemNamed:name inDirectory:nil];
        [impactNode addParticleSystem:hitEffect];
        // Put particle into the scene
        [_gameData.view.scene.rootNode addChildNode:impactNode];
        // Kill the particle after a timer
        [SCNTransaction setCompletionBlock: ^{[impactNode removeFromParentNode];}];
    }
    [SCNTransaction commit];
}

// Put all of the cubes under their parent nodes
-(void) reset
{
    for(int i = 0; i < _secondRoomCubes.count; ++i)
    {
        [SCNTransaction begin];
        SCNNode *cube = _secondRoomCubes[i];
        SCNNode *parent = _secondRoomParents[i];
        [parent addChildNode:cube];
        [cube.physicsBody setType:SCNPhysicsBodyTypeKinematic];
        [SCNTransaction commit];
    }
    
    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration:0.3f];
    [_firstRoomParent addChildNode:self.firstRoomCube];
    [self.firstRoomCube.physicsBody setType:SCNPhysicsBodyTypeKinematic];
    [SCNTransaction setCompletionBlock:^{
        [self.firstRoomCube setPosition:SCNVector3Zero];
        [self.firstRoomCube setRotation:SCNVector4Make(0, 1, 0, 0)];
    }];
    [SCNTransaction commit];
    _collisions = 0;
}
@end
