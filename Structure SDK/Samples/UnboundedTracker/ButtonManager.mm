/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ButtonManager.h"
#import "SCNTools.h"

#import "GameData.h"

@interface ButtonManager()
{
    GameData* _gameData;
    
    SCNNode *_cube;
    SCNNode *_player;
    SCNVector3 _redButtonStartPosition;
    SCNVector3 _blueButtonStartPosition;
    SCNVector3 _blueButtonBaseStartPosition;
    SCNVector3 _blueButtonHatchStartPosition;
    SCNVector3 _blueButtonHatchEndPosition;
    
    BOOL _redButtonPressed;
    BOOL _blueButtonPressed;
    BOOL _isContactedWithoutBeingGrabbed;
    BOOL _isLiftedAndReady;
    
    SCNMaterial *_redButtonMaterial;
    SCNMaterial *_redFloorMaterial;
    SCNMaterial *_blueFloorMaterial;
    SCNMaterial *_blueButtonMaterial;

    BOOL _redFloorGlow;
    BOOL _blueFloorGlow;
    BOOL _redButtonGlow;
    BOOL _blueButtonGlow;
    BOOL _redButtonBlinked;
    
    BOOL _redButtonBlinkDone;
    BOOL _blueButtonBlinkDone;
    BOOL _redFloorBlinkDone;
    BOOL _blueFloorBlinkDone;
    
    // Used to cancel the block for if you reset while the hatch is opening.
    BOOL _isResetting;
}
@end

@implementation ButtonManager


-(id) initWithGameData:(GameData*)gameData
{
    self = [super init];
    
    if(self)
    {
        _gameData = gameData;
        
        self.redButton = [_gameData.view.scene.rootNode childNodeWithName:@"LoadingBay_A_Button" recursively:YES];
        [self setBlueButton:[_gameData.view.scene.rootNode childNodeWithName:@"LoadingBay_B_Button" recursively:YES]];
        [self setBlueButtonHatch:[_gameData.view.scene.rootNode childNodeWithName:@"LoadingBay_Hatch" recursively:YES]];
        [self setBlueButtonBase:[_gameData.view.scene.rootNode childNodeWithName:@"LoadingBay_B_Base" recursively:YES]];
        
        SCNNode *floor = [_gameData.view.scene.rootNode childNodeWithName:@"LoadingBay_Floor" recursively:YES];
        NSArray *floorMaterials = floor.geometry.materials;
        
        for(SCNMaterial *mat in floorMaterials)
        {
            if([mat.name containsString:@"Red"])
            {
                _redFloorMaterial = mat;
            }
            else if([mat.name containsString:@"Blue"])
            {
                _blueFloorMaterial = mat;
            }
        }
        
        [self.redButton setName:@"LoadingBay_A_Button"];
        [self.blueButton setName:@"LoadingBay_B_Button"];
        _redButtonMaterial = self.redButton.geometry.firstMaterial;
        _blueButtonMaterial = self.blueButton.geometry.firstMaterial;

        SCNBox *redbox = [SCNBox boxWithWidth:0.4 height:0.3 length:0.4 chamferRadius:0];
        SCNPhysicsShape *redBoxShape = [SCNPhysicsShape shapeWithGeometry:redbox options:nil];
        SCNPhysicsBody *redBoxBody = [SCNPhysicsBody kinematicBody];

        // Need the convex hull to handle the button outer shape.
        SCNBox *blueButtonGeo = [SCNBox boxWithWidth:1.2 height:0.5 length:1.2 chamferRadius:0];
        SCNPhysicsShape *blueBoxShape = [SCNPhysicsShape shapeWithGeometry:blueButtonGeo options:@{SCNPhysicsShapeTypeKey:SCNPhysicsShapeTypeConvexHull}];
        SCNPhysicsBody *blueBoxBody = [SCNPhysicsBody kinematicBody];
        
        [redBoxBody setPhysicsShape:redBoxShape];
        [redBoxBody setContactTestBitMask:SCNPhysicsCollisionCategoryAll];
        [self.redButton setPhysicsBody:redBoxBody];

        [blueBoxBody setPhysicsShape:blueBoxShape];
        [blueBoxBody setContactTestBitMask:SCNPhysicsCollisionCategoryAll];
        [self.blueButton setPhysicsBody:blueBoxBody];
        
        [self.redButton.physicsBody setMass:0.00000000001];
        [self.blueButton.physicsBody setMass:20.0];
        
        
        //values are from the modeled scene file
        _redButtonStartPosition = SCNVector3Make(2.3606, -0.085482, 0);
        _blueButtonStartPosition = SCNVector3Make(0, 0.5, 0);
        _blueButtonBaseStartPosition = SCNVector3Make(0.2, -1.1522, 3.517);
        _blueButtonHatchStartPosition = SCNVector3Make(0.2, -0.094687, 3.5938);
        _blueButtonHatchEndPosition = SCNVector3Make(0.2, -0.094687, 6.2438);
        
        [self reset];
    }
    
    return self;
}

-(void) physicsWorld:(SCNPhysicsWorld *)world didBeginContact:(SCNPhysicsContact *)contact isGrabbingObject:(BOOL)isGrabbingObject
{
    SCNNode *nodeA = contact.nodeA;
    SCNNode *nodeB = contact.nodeB;
    
    if([nodeA.name containsString:@"capsuleNode"] && [nodeB.name containsString:@"LoadingBay_A_Button"])
    {
        // Player touched the first button.
        [self pressRedButton];
    }
    
    if([nodeA.name containsString:@"LoadingBay_B_Button"] && [nodeB.name containsString:@"FirstRoom_Cube"])
    {
        // Mark this flag so we can press the button after the animation is done.
        if (!isGrabbingObject)
            _isContactedWithoutBeingGrabbed = YES;
        else
            _isContactedWithoutBeingGrabbed = NO;
        
        // Cube touched the second button.
        if (!isGrabbingObject)
        {
            [self pressBlueButton];
        }
    }
}

-(void) physicsWorld:(SCNPhysicsWorld *)world didEndContact:(SCNPhysicsContact *)contact
{
    SCNNode *nodeA = contact.nodeA;
    SCNNode *nodeB = contact.nodeB;
    
    if([nodeA.name containsString:@"LoadingBay_B_Button"] && [nodeB.name containsString:@"FirstRoom_Cube"])
    {
        _isContactedWithoutBeingGrabbed = NO;
    }
}

-(void) updateButtons:(float)time
{
    if(_redButtonPressed)
    {
        if( _redFloorGlow )
        {
            
            float g = sinf(time * 4) * 0.7;
            float a = g < 0? g*-1:g;
            [_redFloorMaterial.emission setContents:[UIColor colorWithRed:a green:a * 0.5 blue:a * 0.5 alpha:1]];
        }
    }
    
    if(_blueButtonPressed)
    {
        if( _blueFloorGlow )
        {
            float g = sinf(time * 4);
            float a = g < 0? g*-1:g;
            [_blueFloorMaterial.emission setContents:[UIColor colorWithRed:a * 0.5 green:a * 0.5 blue:a alpha:1]];
            [_blueButtonMaterial.emission setContents:[UIColor blackColor]];
            [_blueFloorMaterial.diffuse setContents:[UIColor blueColor]];
        }
    }
    
    if( _blueButtonGlow )
    {
        float g = sinf(time * 4);
        float a = g < 0? g*-1:g;
        [_blueButtonMaterial.emission setContents:[UIColor colorWithRed:a * 0.5 green:a * 0.5 blue:a alpha:1]];
    }
    
    if( _redButtonGlow )
    {
        float g = sinf(time * 4) * 0.7;
        float a = g < 0? g * -1: g;
        _redButtonMaterial.emission.contents = [UIColor colorWithRed:a green:a * 0.5 blue:a * 0.5 alpha:1];
    }
}

-(void) blinkRedButton
{
    if (_redButtonBlinked)
    {
        return;
    }
    _redButtonBlinked = YES;
    _redButtonGlow = YES;
}

-(void) pressRedButton
{
    if (_redButtonPressed)
    {
        return;
    }
    _redButtonPressed = YES;
    _isResetting = NO;
    
    // Stop and reset red button glow.
    _redButtonGlow = NO;
    [_redButtonMaterial.emission setContents:[UIColor blackColor]];
    
    // Start red floor glowing
    _redFloorGlow = YES;
    
    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration : 0.2];
    [SCNTransaction setAnimationTimingFunction : [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    [SCNTransaction setCompletionBlock :^{
        [_gameData.cubeManager dropFirstRoomCube];
        [_redFloorMaterial.diffuse setContents:[UIColor redColor]];
        [self openHatch];
    }];
    {
        float deltaY = -0.2;
        self.redButton.position = SCNVector3Make(_redButtonStartPosition.x, _redButtonStartPosition.y + deltaY, _redButtonStartPosition.z);
        [_redButtonMaterial.diffuse setContents:[UIColor redColor]];
        
    }
    [SCNTransaction commit];
}

-(void) openHatch
{
    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration : 3.0];
    [SCNTransaction setAnimationTimingFunction : [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    {
        [self.blueButtonHatch setPosition:_blueButtonHatchEndPosition];
        [SCNTransaction setCompletionBlock :^{
            if(!_isResetting)
            {
                [self liftBButton];
            }
            _isResetting = NO;
        }];
    }
    [SCNTransaction commit];
}

-(void) closeHatch
{
    [SCNTransaction begin];
    {
        [self.blueButtonHatch.presentationNode setPosition:_blueButtonHatchStartPosition];
    }
    [SCNTransaction commit];
}

-(void) liftBButton
{
    SCNVector3 buttonBaseLift = self.blueButtonBase.position;
    
    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration : 1.5];
    [SCNTransaction setAnimationTimingFunction : [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    {
        SCNVector3 openAddition = SCNVector3Make(0, 1.0, 0);
        SCNVector3 BaseUpPosition = [SCNTools addVector:buttonBaseLift toVector:openAddition];
        self.blueButtonBase.position = BaseUpPosition;
        [self.blueButton setPosition:SCNVector3Make(0, 0.5, 0)];
        
        [SCNTransaction setCompletionBlock :^{
            _isLiftedAndReady = YES;
            _blueButtonGlow = YES;
            
            // Now that the animation is done, let's check again if we did not put the box on the
            // button before, during the animation.
            if (_isContactedWithoutBeingGrabbed)
            {
                [self.blueButtonBase.physicsBody resetTransform];
                [self.blueButton.physicsBody resetTransform];
                [self pressBlueButton];
            }
        }];
    }
    [SCNTransaction commit];
}

-(void) pressBlueButton
{
    if(_blueButtonPressed)
    {
        return;
    }
    
    // Do not press the button until the animation is done.
    if (!_isLiftedAndReady)
    {
        return;
    }
    _blueButtonPressed = YES;
    
    // Stop and reset blue button glow
    _blueFloorGlow = YES;
    _blueButtonGlow = NO;
    [_blueButtonMaterial.emission setContents:[UIColor blackColor]];
    
    [SCNTransaction begin];
    [SCNTransaction setAnimationDuration : 1.0];
    [SCNTransaction setAnimationTimingFunction : [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    [SCNTransaction setCompletionBlock :^{
        [_gameData.doorManager openLoadingBayDoors];
        [_redFloorMaterial.diffuse setContents:[UIColor whiteColor]];
        _redFloorGlow = NO;
        [_redFloorMaterial.emission setContents:[UIColor blackColor]];
    }];
    {
        [self.blueButton setPosition:SCNVector3Make(0, 0.35, 0)];
    }
    [SCNTransaction commit];
}

-(bool) getRedButtonPressed
{
    return _redButtonPressed;
}

-(bool) getBlueButtonPressed
{
    return _blueButtonPressed;
}

-(void) setBlueButtonPressed:(bool)pressed
{
    _blueButtonPressed = pressed;
}

-(void) reset
{
    // Reset bools
    _redButtonPressed = NO;
    _blueButtonPressed = NO;
    _redButtonBlinked = NO;
    _isContactedWithoutBeingGrabbed = NO;
    _isLiftedAndReady = NO;
    
    _redFloorGlow = NO;
    _blueFloorGlow = NO;
    _redButtonGlow = NO;
    _blueButtonGlow = NO;
    _isResetting = YES;
    
    _redButtonBlinkDone = NO;
    _blueButtonBlinkDone = NO;
    _redFloorBlinkDone = NO;
    _blueFloorBlinkDone = NO;

    [SCNTransaction begin];
    [self.blueButtonHatch setHidden:NO];
    [_redButtonMaterial.emission setContents:[UIColor blackColor]];
    [_blueFloorMaterial.emission setContents:[UIColor blackColor]];
    [_blueButtonMaterial.emission setContents:[UIColor blackColor]];
    [_redFloorMaterial.emission setContents:[UIColor blackColor]];
    [_redFloorMaterial.diffuse setContents:[UIColor whiteColor]];
    [_blueFloorMaterial.diffuse setContents:[UIColor whiteColor]];
    [SCNTransaction commit];
    
    [self.redButton removeAllActions];
    [self.redButton removeAllAnimations];
    [SCNTransaction begin];
    // Raise the red button back up
    [self.redButton setPosition:_redButtonStartPosition];
    [self.redButton.physicsBody resetTransform];
    [SCNTransaction commit];
    
    [self.blueButton removeAllActions];
    [self.blueButton removeAllAnimations];
    [SCNTransaction begin];
    // Raise the blue button back up
    [self.blueButton setPosition:_blueButtonStartPosition];
    [self.blueButton.physicsBody resetTransform];
    [SCNTransaction commit];
    
    [self.blueButtonBase removeAllActions];
    [self.blueButtonBase removeAllAnimations];
    [SCNTransaction begin];
    // Lower the button base
    [self.blueButtonBase setPosition:_blueButtonBaseStartPosition];
    [SCNTransaction commit];
    
    [self.blueButtonHatch removeAllActions];
    [self.blueButtonHatch removeAllAnimations];
    [SCNTransaction begin];
    // Close the button hatch
    [self.blueButtonHatch setPosition:_blueButtonHatchStartPosition];
    [SCNTransaction commit];
    
}
@end
