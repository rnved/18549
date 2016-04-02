/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController.h"
#import "Reticle.h"

@interface ViewController (Game) <SCNPhysicsContactDelegate>

// Called by various rendering and delegates in the ViewController
-(void) loadGame;
-(void) updatePlayerWithTrackerPose:(const TrackerUpdate&)trackerUpdate locked:(BOOL)isLocked deltaTime:(float)time;
-(void) updateGameTimeSinceStart:(float)time;

// Control of game state
-(void) startGame;
-(void) resetGameState;
-(void) resetGameStateInSceneKitThread;
-(void) pauseGame;
-(bool) gamePaused;
-(void) endGame;
-(void) jumpToLab;
// Incoming UI input
-(void) readViewLock;
@end
