/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController+Game.h"

#import "GameData.h"
#import "Reticle.h"
#import "SCNTools.h"
#import "MotionLogs.h"

@implementation ViewController (Game)

#pragma mark - various rendering and delegates in the viewcontroller

-(void) loadGame
{
    // Create the game elements holder.
    _gameData = [[GameData alloc] init];
    
    // Loads the scene from dae files
    [self loadScene];
    
    // Gets the scene's physics world and assigns ourself a delegate
    [_gameData.view.scene.physicsWorld setContactDelegate:self];
    
    // Restart tutorial
    [self toTutorialStage:TutorialStage::NotStarted];
}

- (void) loadScene
{
    //------Scene initialization------//
    _gameData.view = (SCNView *)self.view;
    __weak ViewController *weakSelf = self;
    [_gameData.view setDelegate:weakSelf];
    
    // Read in plist with room dae models, each entry in the plist can be replaced
    //  with any other dae scene
    _gameData.view.scene = [SCNTools loadSceneFromPlist:@"GameWorld"];
    
    // This parses the dae scene and replaces nodes named light with an actual scenekit light
    //  TODO: to improve performance significantly on the iPad 4, comment out the following line
    //  to not add the spotlights
    [SCNTools setupLightsInScene:_gameData.view.scene];
    
    //------player initialization------//
    _gameData.player = [[Player alloc] initWithGameData:_gameData];
    
    //------init scenekit scene------//
    _gameData.view.pointOfView = _gameData.player.pov;
    // TODO: hide statistics if you don't want to see bottom bar.
    _gameData.view.showsStatistics = YES;
    _gameData.view.backgroundColor = [UIColor blackColor];
    _gameData.view.preferredFramesPerSecond = 30;
    _gameData.view.playing = YES;
    
    // Assign the UI buttons to th player so they can be updated
    //  and cursor screen element here
    _gameData.player.warpButton = self.warpButton;
    _gameData.player.actionButton = self.actionButton;
    
    //create Reticle for player
    float reticleSize = 64;
    CGRect reticleRect = CGRectMake(self.reticleView.frame.size.width/2-reticleSize/2, self.reticleView.frame.size.height/2-reticleSize/2,reticleSize,reticleSize);
    Reticle *reticle = [[Reticle alloc] initWithFrame:reticleRect];
    [self.reticleView addSubview:reticle.view];
    [self.reticleView setUserInteractionEnabled:NO];
    _gameData.player.reticle = reticle;
    
    //------floor plane------//
    // Use floor for waypoint navigation
    //  make the floor invisible and not render.
    //  the ray cast for postioning the warp point
    //  looks for a scnNode named @"floor" so make
    //  sure that you don't name any other node
    //  the same
    SCNFloor *floorGeo = [SCNFloor floor];
    floorGeo.reflectivity = 0;
    SCNNode*floor = [SCNNode nodeWithGeometry:floorGeo];
    [floor setName:@"floor"];
    [floor setPosition:SCNVector3Make(0.0f, 0.0f, 0.0f)];
    [floor setPhysicsBody:[SCNPhysicsBody staticBody]];
    [floor.physicsBody setContactTestBitMask:SCNPhysicsCollisionCategoryAll];
    [floor.geometry.firstMaterial setTransparency:0];
    [floor.geometry.firstMaterial setReadsFromDepthBuffer:NO];
    [floor.geometry.firstMaterial setWritesToDepthBuffer:NO];
    [_gameData.view.scene.rootNode addChildNode:floor];
    
    //------monolith------//
    // In the second room
    SCNNode *monolith = [SCNNode node];
    SCNNode *monolithGeo = [SCNNode nodeWithGeometry:[SCNBox boxWithWidth:2.0 height:4.0 length:0.4 chamferRadius:0.01]];
    [monolithGeo setPosition:SCNVector3Make(0, 2.0, 0)];
    [monolithGeo.geometry.firstMaterial.diffuse setContents:[UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:1.0]];
    [monolith addChildNode:monolithGeo];
    [_gameData.view.scene.rootNode addChildNode:monolith];
    [monolith setPosition:SCNVector3Make(-30, 0, 5)];
    
    //------physics world-------//
    // This sets the scenekit's gravity up
    //  if you don't do this then your physics objects will float
    [_gameData.view.scene.physicsWorld setGravity:SCNVector3Make(0.0, -9.8, 0.0)];
    [_gameData.view.scene.physicsWorld setTimeStep:0.5 * 1.0/((SCNView *)self.view).preferredFramesPerSecond];
    
    //most lights in the scene don't fill in the entire scene.
    //so add in an ambientLight to fill in the darkness
    //if you don't want any ambient lighting then you can skip this
    SCNNode *ambientLight = [SCNNode node];
    [ambientLight setName:@"ambientLight"];
    [ambientLight setPosition:SCNVector3Make(0, 5, 0)];
    [ambientLight setLight:[SCNLight light]];
    [ambientLight.light setName:@"ambientLight"];
    [ambientLight.light setType:SCNLightTypeAmbient];
    [ambientLight.light setColor:[UIColor colorWithWhite:0.5 alpha:0]];
    [_gameData.view.scene.rootNode addChildNode:ambientLight];
    
    // TODO: comment out the lines below to remove our custom game logic.
    {
        //-------setup cubes in both rooms-------//
        _gameData.cubeManager = [[CubeManager alloc] initWithGameData:_gameData];
        
        //-------setup door and trigger volumes-------//
        _gameData.doorManager = [[DoorManager alloc] initWithGameData:_gameData];
        
        //-------setup button manager------//
        _gameData.buttonManager = [[ButtonManager alloc] initWithGameData:_gameData];
        
        //------pointer for feedback------//
        _gameData.pointerNode = [[PointerNode alloc] initWithGameData:_gameData];
    }
}

//this updates the player's position in the world from the unbound tracking
-(void) updatePlayerWithTrackerPose:(const TrackerUpdate&)trackerUpdate locked:(BOOL)isLocked deltaTime:(float)time
{
    [_gameData.player updateWithTrackerPose:trackerUpdate locked:isLocked deltaTime:time];
    
    [MotionLogs logGameCameraPose:_gameData.player.pov.presentationNode.worldTransform atTime:_timeTracker.timeSinceStart()];
}

// Physics delegate.
-(void) physicsWorld:(SCNPhysicsWorld *)world didBeginContact:(SCNPhysicsContact *)contact
{
    // Cube collision tests
    [_gameData.cubeManager physicsWorld:world didBeginContact:contact];
    
    // Checks for the player's touching a trigger to open doors
    [_gameData.doorManager physicsWorld:world didBeginContact:contact];
    
    // Check buttons, there are only two of them
    [_gameData.buttonManager physicsWorld:world didBeginContact:contact isGrabbingObject:(_gameData.player.attachedObject != nil)];
}

-(void) updateGameTimeSinceStart:(float)time
{
    // Used for warping around, picking up and dropping the cubes in the scene
    [_gameData.player updateSceneKit];
    
    // The button manager needs to use time to glow the buttons
    [_gameData.buttonManager updateButtons:time];
    [self updateTutorialSceneKit];
    [_gameData.pointerNode updatePointerNode];
}

// This is called in the main thread.
- (void) updateTutorialSceneKit
{
    // This function runs on each frame to check changes in tutorial stage.
    
    TutorialStage newTutorialStage = _tutorialStage;
    
    switch (_tutorialStage)
    {
        case TutorialStage::NeedToWalkOnFloorButton:
        {
            if (_gameData.buttonManager.getRedButtonPressed)
                newTutorialStage = TutorialStage::NeedToGrabFirstCube;
            break;
        }
            
        case TutorialStage::NeedToGrabFirstCube:
        {
            if ([_gameData.player canGrab])
                [self setFlashingElement:self.actionButton];
            else
                [self setFlashingElement:nil];
            
            if (_gameData.player.attachedObject)
                newTutorialStage = TutorialStage::NeedToDropCubeOnButton;
            
            if ([_gameData.buttonManager getBlueButtonPressed])
                newTutorialStage = TutorialStage::NeedToTryWarp;
            
            break;
        }
            
        case TutorialStage::NeedToDropCubeOnButton:
        {
            if (!_gameData.player.attachedObject)
                newTutorialStage = TutorialStage::NeedToGrabFirstCube;
            
            if ([_gameData.buttonManager getBlueButtonPressed])
                newTutorialStage = TutorialStage::NeedToTryWarp;
            
            break;
        }
            
        case TutorialStage::NeedToTryWarp:
        {
            if ([_gameData.player canWarp] &&
                ![_gameData.player warpButtonHasBeenPressed])
                [self setFlashingElement:self.warpButton];
            else
                [self setFlashingElement:nil];
            
            if (![_gameData.buttonManager getBlueButtonPressed])
                newTutorialStage = TutorialStage::NeedToDropCubeOnButton;
            
            if (15.0f < [SCNTools vectorMagnitude:[SCNTools getWorldPos:_gameData.player.capsule]])
                newTutorialStage = TutorialStage::Finished;
            
            break;
        }
            
        case TutorialStage::Finished:
        {
            break;
        }
            
        default:
            //undefined tutorial area.
            break;
    }
    
    if (newTutorialStage != _tutorialStage)
    {
        // We change the tutorial in the main thread because it updates several UIKit elements.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self toTutorialStage:newTutorialStage];
        });
    }
}

- (void)toTutorialStage:(TutorialStage)newTutorialStage
{
    // Should be called ONCE on a tutorial stage change.
    //  This should ONLY be called in the main thread.
    NSAssert([NSThread currentThread] == [NSThread mainThread], @"toTutorialStage called from a thread that wasn't main!");
    
    switch (newTutorialStage)
    {
        case TutorialStage::NeedToWalkOnFloorButton:
        {
            [self defineMission:@"Current Mission: Walk onto the red pressure switch."];
            
            // Point the player's attention to the red button
            [_gameData.pointerNode setTarget:_gameData.buttonManager.redButton];
            [_gameData.buttonManager blinkRedButton];

            // Tell the player to walk to the red button
            [[AudioManager sharedAudioManager] playAudio:@"vo-welcome-to-2715" interruptAudio:YES];
            [self.actionButton setHidden:YES];
            break;
        }
            
        case TutorialStage::NeedToGrabFirstCube:
        {
            [self defineMission:@"Current Mission: Pick up a block."];
            [_gameData.pointerNode setTarget:_gameData.cubeManager.firstRoomCube];
            
            if (_tutorialStage < TutorialStage::NeedToGrabFirstCube)
            {
                [[AudioManager sharedAudioManager] playAudio:@"vo-pick-up-box" interruptAudio:YES];
            }
            if (_tutorialStage > TutorialStage::NeedToGrabFirstCube)
            {
                // Stop any existing voiceover
                [[AudioManager sharedAudioManager] stopLastAudio];
            }
            
            [self.actionButton setTitle:@"Grab" forState:UIControlStateNormal];
            [self.actionButton setHidden:NO];
            break;
        }
            
        case TutorialStage::NeedToDropCubeOnButton:
        {
            [self defineMission:@"Current Mission: Drop the block on the blue pressure switch."];
            [self setFlashingElement:nil];
            [_gameData.pointerNode setTarget:_gameData.buttonManager.blueButton];
            
            if (_tutorialStage < TutorialStage::NeedToDropCubeOnButton)
                [[AudioManager sharedAudioManager] playAudio:@"vo-drop-the-box" interruptAudio:YES];
            break;
        }
            
        case TutorialStage::NeedToTryWarp:
        {
            [self defineMission:@"Current Mission: Go to the next room by warping."];
            [_gameData.player setWarpEnabled:YES];
            
            if (_tutorialStage < TutorialStage::NeedToTryWarp)
            {
                [[AudioManager sharedAudioManager] playAudio:@"vo-warping" interruptAudio:YES];
                [_gameData.pointerNode setTarget:_gameData.doorManager.door2Collider];
            }
            break;
        }
            
        case TutorialStage::Finished:
        {
            [self defineMission:@"Current Mission: Explore the room."]; //Room 2
            [self setFlashingElement:nil];
            [_gameData.player setWarpEnabled:YES];
            [self.actionButton setTitle:@"" forState:UIControlStateNormal];
            [self.actionButton setHidden:NO];
            [_gameData.pointerNode setTarget:nil];
            break;
        }
            
        default:
        {
            // Nothing to do.
        }
    }
    
    // Make sure warp is disabled if not yet there.
    if (newTutorialStage < TutorialStage::NeedToTryWarp)
    {
        [_gameData.player setWarpEnabled:NO];
    }
    
    _tutorialStage = newTutorialStage;
}

#pragma mark - Game flow
-(void) startGame
{
    [_gameData.view.scene setPaused:NO];
    [_gameData.player setAllowMovement:YES];

    [[AudioManager sharedAudioManager] startAudioEngine];

    [self resetGameState];
}

- (void)resetGameState
{
    // Called when the view appears or when a reset is triggered by button press.
    // We set a bool so the reset logic will be performed in the SceneKit thread.
    _gameData.player.startRoom = 1;
    _needsFullGameStateReset = true;
}

-(void) pauseGame
{
    [_gameData.view.scene setPaused:YES];
    [_gameData.player setAllowMovement:NO];
    [[AudioManager sharedAudioManager] stopAudioEngine];
}

-(bool) gamePaused;
{
    return _gameData.view.scene.paused;
}

-(void) endGame
{
    SCNView *scnView = (SCNView *)self.view;
    scnView.scene = nil;
}

- (void)resetGameStateInSceneKitThread
{
    // Do player reset first or the camera might push the player out on reset
    [_gameData.player reset];
    
    [MotionLogs resetPlayback];
    
    [_gameData.doorManager reset];
    [_gameData.buttonManager reset];
    [_gameData.cubeManager reset];
    [_gameData.pointerNode setTarget:_gameData.buttonManager.redButton];
    
    TutorialStage newTutorialStage = TutorialStage::NeedToWalkOnFloorButton;
    
    // If we start in room 2, skip the tutorial.
    if (_gameData.player.startRoom >= 2)
    {
        newTutorialStage = TutorialStage::Finished;
        [_gameData.cubeManager dropSecondRoomCubes];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self toTutorialStage:newTutorialStage];
    });
    
    _timeTracker = TimeTracker();
}

#pragma mark - Game UI updates
BOOL missionTextAnimating = NO;
- (void)defineMission:(NSString*) missionText
{
    // This should ONLY be called in the main thread.
    NSAssert([NSThread currentThread] == [NSThread mainThread], @"defineMission called from a thread that wasn't main!");
    
    if ([missionText isEqualToString:self.missionLabel.text])
    {
        return; // already set.
    }
    
    // Mission displayed to user
    if (missionText.length == 0)
    {
        [self.missionLabel setAlpha:0];
        return;
    }
    
    [self.missionLabel setAlpha:1.0];
    [self.missionLabel setText:missionText];
    
    if (!missionTextAnimating)
    {
        missionTextAnimating = YES;
        
        self.missionLabel.transform = CGAffineTransformMakeScale(1.0, 1.0);
        [UIView animateWithDuration:0.2f
                         animations:^{self.missionLabel.transform = CGAffineTransformMakeScale(1.2, 1.2);}
                         completion:^(BOOL finished){ [UIView animateWithDuration:0.2f
                                                                            delay:0.0
                                                                          options:0
                                                                       animations:^{ self.missionLabel.transform = CGAffineTransformIdentity;}
                                                                       completion:^(BOOL finished){ missionTextAnimating = NO; }];}];
    }
}

// This method handles an animation associated to a UIKit element. Used to attract user attention.
-(void) setFlashingElement:(UIView*)elementToFlash
{
    // Only one flashing element at a time.
    static UIView *_flashingElement;
    
    // It isn't guaranteed that this function will be called in the main thread
    if (_flashingElement == elementToFlash)
    {
        return;
    }
    
    if (_flashingElement)
    {
        // Cancel existing flash
        UIView *cancelFlashingElement = _flashingElement;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3
                                  delay:0.0
                                options:UIViewAnimationOptionCurveEaseInOut |
             UIViewAnimationOptionBeginFromCurrentState |
             UIViewAnimationOptionAllowUserInteraction
                             animations:^{
                                 [cancelFlashingElement setAlpha:1.0f];
                                 [cancelFlashingElement setTransform:CGAffineTransformMakeScale(1.0, 1.0)];
                             }
                             completion:^(BOOL finished){
                                 // Do nothing
                             }];
        });
    }
    
    // Start new flash
    _flashingElement = elementToFlash;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        [_flashingElement setAlpha:1.0f];
        [_flashingElement setTransform:CGAffineTransformMakeScale(1.0, 1.0)];
        
        [UIView animateWithDuration:0.3
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut |
         UIViewAnimationOptionRepeat |
         UIViewAnimationOptionAutoreverse |
         UIViewAnimationOptionAllowUserInteraction
                         animations:^{
                             [_flashingElement setTransform:CGAffineTransformMakeScale(1.2, 1.2)];
                         }
                         completion:^(BOOL finished){
                             // Do nothing
                         }];
    });
}

#pragma mark - Audio

-(void) readViewLock
{
    [[AudioManager sharedAudioManager] playAudio:@"vo-view-locking" interruptAudio:YES];
}

-(void) jumpToLab
{
    [self toTutorialStage:TutorialStage::Finished];
    [_gameData.player jumpToLab];
}

@end
