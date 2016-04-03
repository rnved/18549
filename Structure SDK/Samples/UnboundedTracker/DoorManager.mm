/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "DoorManager.h"
#import "SCNTools.h"

#import "GameData.h"

// Doors' visual parts are already loaded in the dae's: LoadingBay.dae and Lab.dae
//  We fetch them by searching by name, and prepare to animate them later
//  The visual geometry of the doors is independent of their trigger volume,
//  As well as the collision volumes.
//  Both trigger and collision volumes are created manually here (not loaded from the dae's)

@interface DoorManager ()
{
    GameData* _gameData;
    
    SCNNode *_firstTrigger;
    
    SCNNode *_loadingBay_DoorUpper;
    SCNNode *_loadingBay_DoorLower;
    SCNNode *_labEntrance_DoorUpper;
    SCNNode *_labEntrance_DoorLower;
    
    SCNVector3 _loadingBay_DoorUpperHomePosition;
    SCNVector3 _loadingBay_DoorLowerHomePosition;
    
    SCNVector3 _labEntrance_DoorUpperHomePosition;
    SCNVector3 _labEntrance_DoorLowerHomePosition;
        
    SCNNode *_airLock1;
    float _openLowerY;
    float _openUpperY;
    float _closeLowerY;
    float _closeUpperY;
    bool _firstTriggerActivated;
}
@end

@implementation DoorManager

bool allowDeactivation = NO;

-(id) initWithGameData:(GameData*)gameData
{
    self = [super init];
    if(self)
    {
        _gameData = gameData;
        
        [self setDoors];
        [self createTriggerVolumes];
        [self createDoorColliders];
        
        // Numbers tuned to represent top and bottom of door movement.
        _openLowerY = -1.0;
        _openUpperY = 2.5498;
        
        _closeLowerY = 1.0;
        _closeUpperY = -2.5498;

        [self reset];
    }
    return self;
}

-(void) setDoors
{
    _loadingBay_DoorUpper = [_gameData.view.scene.rootNode childNodeWithName:@"LoadingBay_DoorUpper" recursively:YES];
    _loadingBay_DoorUpperHomePosition = _loadingBay_DoorUpper.position;
    _loadingBay_DoorLower = [_gameData.view.scene.rootNode childNodeWithName:@"LoadingBay_DoorLower" recursively:YES];
    _loadingBay_DoorLowerHomePosition = _loadingBay_DoorLower.position;
    _labEntrance_DoorUpper = [_gameData.view.scene.rootNode childNodeWithName:@"Lab_EntranceDoorUpper" recursively:YES];
    _labEntrance_DoorUpperHomePosition = _labEntrance_DoorUpper.position;
    _labEntrance_DoorLower = [_gameData.view.scene.rootNode childNodeWithName:@"Lab_EntranceDoorLower" recursively:YES];
    _labEntrance_DoorLowerHomePosition = _labEntrance_DoorLower.position;
    
    // Put the corridor and door geometries into the airlock nodes
    _airLock1 = [SCNNode node];
    [_airLock1 setName:@"AirLock1"];
    
    [_loadingBay_DoorUpper setName:@"AirLock1_In_DoorUpper"];
    [_loadingBay_DoorLower setName:@"AirLock1_In_DoorLower"];
    [_labEntrance_DoorLower setName:@"AirLock1_Out_DoorUpper"];
    [_labEntrance_DoorUpper setName:@"AirLock1_Out_DoorLower"];
    
    [_airLock1 addChildNode:_loadingBay_DoorLower];
    [_airLock1 addChildNode:_loadingBay_DoorUpper];
    [_airLock1 addChildNode:[_gameData.view.scene.rootNode childNodeWithName:@"LoadingBay_Corridor" recursively:YES]];
    
    [_gameData.view.scene.rootNode addChildNode:_airLock1];
}

-(void) createTriggerVolumes
{
    SCNGeometry *box = [SCNBox boxWithWidth:2 height:5 length:6 chamferRadius:0];
    SCNNode *firstTriggerNode = [SCNNode node];
    firstTriggerNode.name = @"firstTrigger";
    firstTriggerNode.physicsBody = [SCNPhysicsBody kinematicBody];
    firstTriggerNode.geometry = box;
    firstTriggerNode.physicsBody.physicsShape = [SCNPhysicsShape shapeWithGeometry:box options:nil];
    [firstTriggerNode.physicsBody setContactTestBitMask:SCNPhysicsCollisionCategoryAll];
    
    // We use a small non-zero mass to make the physics simulation run (zero mass appears to be ignored)
    firstTriggerNode.physicsBody.mass = 0.00000000001;
    
    // Both share geometry
    [firstTriggerNode.geometry.firstMaterial setTransparency:0];
    [firstTriggerNode.geometry.firstMaterial setLightingModelName:SCNLightingModelConstant];
    [firstTriggerNode.geometry.firstMaterial setLitPerPixel:NO];
    [firstTriggerNode.geometry.firstMaterial setReadsFromDepthBuffer:NO];
    [firstTriggerNode.geometry.firstMaterial setWritesToDepthBuffer:NO];
    
    [_gameData.view.scene.rootNode addChildNode:firstTriggerNode];
    
    [firstTriggerNode setPosition:SCNVector3Make(-12.5, 2.5, 0)];
}

-(void) createDoorColliders;
{
    [self setDoor1Collider:[SCNNode node]];
    [self setDoor2Collider:[SCNNode node]];
    [self setDoor3Collider:[SCNNode node]];
    
    [self.door1Collider setName:@"door1Collider"];
    [self.door2Collider setName:@"door2Collider"];
    [self.door3Collider setName:@"door3Collider"];
    
    SCNGeometry *box1 = [SCNBox boxWithWidth:1.5 height:5 length:4 chamferRadius:0];
    SCNGeometry *box2 = [SCNBox boxWithWidth:1.5 height:5 length:4 chamferRadius:0];
    SCNGeometry *box3 = [SCNBox boxWithWidth:1.5 height:5 length:4 chamferRadius:0];
    
    SCNPhysicsShape *blocker1PhysShape = [SCNPhysicsShape shapeWithGeometry:box1 options:nil];
    SCNPhysicsShape *blocker2PhysShape = [SCNPhysicsShape shapeWithGeometry:box2 options:nil];
    SCNPhysicsShape *blocker3PhysShape = [SCNPhysicsShape shapeWithGeometry:box3 options:nil];

    SCNPhysicsBody *blocker1Body = [SCNPhysicsBody staticBody];
    SCNPhysicsBody *blocker2Body = [SCNPhysicsBody staticBody];
    SCNPhysicsBody *blocker3Body = [SCNPhysicsBody staticBody];
    
    [blocker1Body setPhysicsShape:blocker1PhysShape];
    [blocker2Body setPhysicsShape:blocker2PhysShape];
    [blocker3Body setPhysicsShape:blocker3PhysShape];
    
    [blocker1Body setContactTestBitMask:SCNPhysicsCollisionCategoryAll];
    [blocker2Body setContactTestBitMask:SCNPhysicsCollisionCategoryAll];
    [blocker3Body setContactTestBitMask:SCNPhysicsCollisionCategoryAll];
    
    [self.door1Collider setPhysicsBody:blocker1Body];
    [self.door2Collider setPhysicsBody:blocker2Body];
    [self.door3Collider setPhysicsBody:blocker3Body];
    
    [self.door1Collider setPosition:SCNVector3Make(-7.4, 2.5, 0)];
    [self.door2Collider setPosition:SCNVector3Make(-18.5, 2.5, 0)];
    [self.door3Collider setPosition:SCNVector3Make(-40.0, 2.5, 0)];
    
    [_gameData.view.scene.rootNode addChildNode:self.door1Collider];
    [_gameData.view.scene.rootNode addChildNode:self.door2Collider];
    [_gameData.view.scene.rootNode addChildNode:self.door3Collider];
}

-(void) physicsWorld:(SCNPhysicsWorld *)world didBeginContact:(SCNPhysicsContact *)contact
{
    SCNNode *nodeA = contact.nodeA;
    SCNNode *nodeB = contact.nodeB;
    
    if([nodeA.name containsString:@"capsuleNode"] && [nodeB.name containsString:@"firstTrigger"])
    {
        [self touchedFirstTrigger];
    }
}

-(void) openLoadingBayDoors
{
    [self.door1Collider setHidden:YES];
    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration : 1.0];
    [SCNTransaction setAnimationTimingFunction : [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    {
        // Raise upper doors
        SCNVector3 upDoorStart = _loadingBay_DoorUpper.position;
        SCNVector3 upDoorDelta = SCNVector3Make(0, _openUpperY, 0);
        SCNVector3 upperDoorOpenedPosition = [SCNTools addVector:upDoorStart toVector:upDoorDelta];
        _loadingBay_DoorUpper.position = upperDoorOpenedPosition;
        
        // Drop lower doors
        SCNVector3 lowDoorStartPos = _loadingBay_DoorLower.position;
        SCNVector3 lowDoorDelta = SCNVector3Make(0, _openLowerY, 0);
        SCNVector3 lowDoorEndPos = [SCNTools addVector:lowDoorStartPos toVector:lowDoorDelta];
        _loadingBay_DoorLower.position = lowDoorEndPos;
        SCNPhysicsBody *doorCollision = _loadingBay_DoorUpper.physicsBody;
        [doorCollision setMass:0.00000000001];
    }
    [SCNTransaction commit];
    
    [[AudioManager sharedAudioManager] playAudio:@"Door_Open" interruptAudio:NO];
}

-(void) closeLoadingBayDoors
{
    [self.door1Collider setHidden:NO];
    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration : 1.0];
    [SCNTransaction setAnimationTimingFunction : [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
    {
        // Raise upper doors
        SCNVector3 upDoorStart = _loadingBay_DoorUpper.position;
        SCNVector3 upDoorDelta = SCNVector3Make(0, _closeUpperY, 0);
        SCNVector3 upperDoorEndPos = [SCNTools addVector:upDoorStart toVector:upDoorDelta];
        _loadingBay_DoorUpper.position = upperDoorEndPos;
        
        // Drop lower doors
        SCNVector3 lowDoorStartPos = _loadingBay_DoorLower.presentationNode.position;
        SCNVector3 lowDoorDelta = SCNVector3Make(0, _closeLowerY, 0);
        SCNVector3 lowDoorEndPos = [SCNTools addVector:lowDoorStartPos toVector:lowDoorDelta];
        _loadingBay_DoorLower.position = lowDoorEndPos;
    }
    [SCNTransaction commit];
}

-(void) openLabEntranceDoors
{
    [self.door2Collider setHidden:YES];
    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration : 1.0];
    [SCNTransaction setAnimationTimingFunction : [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
    {
        // Raise upper doors
        SCNVector3 upDoorStart = _labEntrance_DoorUpper.position;
        SCNVector3 upDoorDelta = SCNVector3Make(0, _openUpperY, 0);
        SCNVector3 upperDoorEndPos = [SCNTools addVector:upDoorStart toVector:upDoorDelta];
        _labEntrance_DoorUpper.position = upperDoorEndPos;
        
        // Drop lower doors
        SCNVector3 lowDoorStartPos = _labEntrance_DoorLower.presentationNode.position;
        SCNVector3 lowDoorDelta = SCNVector3Make(0, _openLowerY, 0);
        SCNVector3 lowDoorEndPos = [SCNTools addVector:lowDoorStartPos toVector:lowDoorDelta];
        _labEntrance_DoorLower.position = lowDoorEndPos;
    }
    [SCNTransaction commit];
    
    [[AudioManager sharedAudioManager] playAudio:@"Door_Open" interruptAudio:NO];
}

-(void) closeLabEntranceDoors
{
    [self.door2Collider setHidden:NO];
    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration : 1.0];
    [SCNTransaction setAnimationTimingFunction : [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
    {
        // Raise upper doors
        SCNVector3 upDoorStart = _labEntrance_DoorUpper.position;
        SCNVector3 upDoorDelta = SCNVector3Make(0, _closeUpperY, 0);
        SCNVector3 upperDoorEndPos = [SCNTools addVector:upDoorStart toVector:upDoorDelta];
        _labEntrance_DoorUpper.position = upperDoorEndPos;
        
        // Drop lower doors
        SCNVector3 lowDoorStartPos = _labEntrance_DoorLower.presentationNode.position;
        SCNVector3 lowDoorDelta = SCNVector3Make(0, _closeLowerY, 0);
        SCNVector3 lowDoorEndPos = [SCNTools addVector:lowDoorStartPos toVector:lowDoorDelta];
        _labEntrance_DoorLower.position = lowDoorEndPos;
    }
    [SCNTransaction commit];
}

-(void) touchedFirstTrigger
{
    if(_firstTriggerActivated)
        return;
    
    [self closeLoadingBayDoors];
    [self openLabEntranceDoors];
    [_gameData.cubeManager dropSecondRoomCubes];
    _firstTriggerActivated = YES;
}

-(void) reset
{
    [_loadingBay_DoorUpper setPosition:_loadingBay_DoorUpperHomePosition];
    [_loadingBay_DoorLower setPosition:_loadingBay_DoorLowerHomePosition];
    [_labEntrance_DoorUpper setPosition:_labEntrance_DoorUpperHomePosition];
    [_labEntrance_DoorLower setPosition:_labEntrance_DoorLowerHomePosition];
    _firstTriggerActivated = NO;
}
@end
