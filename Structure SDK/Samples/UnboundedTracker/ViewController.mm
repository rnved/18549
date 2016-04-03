/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController.h"

#import "SCNTools.h"
#import "AppDelegate.h"

// ViewController categories
#import "ViewController+Touch.h"
#import "ViewController+Camera.h"
#import "ViewController+Sensor.h"
#import "ViewController+IMU.h"
#import "ViewController+SLAM.h"
#import "ViewController+Game.h" //customizable game logic

#import "MotionLogs.h"

// These variables are used to add smart delays for tracking error messages.
struct TrackingErrorMessageState
{
    NSTimeInterval timeSinceFirstTooCloseTrackingError = 10;
    NSTimeInterval timeSinceLastTooCloseTrackingError = 10;
    
    NSTimeInterval timeSinceFirstBadTrackingError = 10;
    NSTimeInterval timeSinceLastBadTrackingError = 10;
};

@interface ViewController ()
{
    // Useful variables to determine was error message to show.
    TrackingErrorMessageState _trackingErrorMessageState;
}
@end

@implementation ViewController

#pragma mark - ViewController Setup

- (void)dealloc
{
    // Stop grabbing images.
    [self stopColorCamera];
    
    // Tell the (Game) category to clean up scenekit
    [self endGame];
}

- (void)setupTrackerDevices
{
    _structureStatusUI = [[StructureStatusUI alloc] initInViewController:self];
    
    [self setupIMU];
    
    [self startColorCamera];
    
    [self setupStructureSensor];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Setup notifications and initial UI state.
    [self setupUserInterface];
    
    // Setup gesture recognition for pan lock behavior.
    [self setupGestures];

    // Load the SceneKit game.
    [self loadGame];
    
    // Init Motion Logs from iTunes file system path.
    [MotionLogs loadLogsWithRootNode:_gameData.view.scene.rootNode andPlayButton:self.playMotionLogsButton];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:NO];
    
    // Start playing the scene.
    [self startGame];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    // Setup Structure Sensor, color camera and IMU for tracking.
    [self setupTrackerDevices];
    
    [self connectToStructureAndStartStreaming];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    // Pause sceneKit for backgrounding
    [self pauseGame];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
}

- (void)appDidBecomeActive
{
    // Try to connect to the Structure Sensor and stream if necessary.
    [self connectToStructureAndStartStreaming];
    
    // Try to start it again here in case the user changed the restriction settings while we were in the background.
    [self startColorCamera];
}

- (void)appWillResignActive
{
    // Uncomment to exit when backgrounded
    // exit (0);
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)setupUserInterface
{
    // Allow the application from going to IDLE state.
    [UIApplication.sharedApplication setIdleTimerDisabled:NO];
    
    // Make sure the status bar is hidden.
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationSlide];
    
    // Make sure we get notified when the app becomes active to start/restore the sensor state if necessary.
    __weak ViewController *weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserver:weakSelf
                                             selector:@selector(appDidBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:weakSelf
                                             selector:@selector(appWillResignActive)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    // Hide UI buttons until they're needed
    [self.warpButton setHidden:YES];
    [self.actionButton setHidden:YES];
    
    [_lockHintImage setImage:[UIImage animatedImageNamed:@"PersonMove" duration:3.0f]];
    
    [_recordButton setHidden:YES];
    
}

// Make sure the status bar is disabled (iOS 7+)
- (BOOL)prefersStatusBarHidden
{
    return YES;
}

#pragma mark -  SceneKit Renderer Delegate Methods

- (void)renderer:(id <SCNSceneRenderer>)aRenderer updateAtTime:(NSTimeInterval)time
{
    // Make sure the tracker thread runs with the same priority as the SceneKit thread.
    // Otherwise there is a risk the tracker will lag behind and slow down everything.
    _slamState.trackerThread.threadPriority = [NSThread currentThread].threadPriority;
    
    if (_needsFullGameStateReset)
    {
        _needsFullGameStateReset = false;
        // We should avoid accessing SceneKit scene outside of the SceneKit thread, so we perform most
        // reset actions here.
        [self resetGameStateInSceneKitThread];
    }
    
    // Nothing to do if the game is paused.
    if (self.gamePaused)
        return;
    
    if (_slamState.isTracking)
    {
        NSAssert(_slamState.initialized, @"How did we enable tracking without an initialization?");
        double previousFrameTimestamp = _slamState.lastSceneKitTrackerUpdateProcessed.timestamp;
        _slamState.lastSceneKitTrackerUpdateProcessed = [self getMoreRecentTrackerUpdate:previousFrameTimestamp];
        
        if (_slamState.lastSceneKitTrackerUpdateProcessed.couldEstimatePose)
        {
            [self updatePlayerWithTrackerPose:_slamState.lastSceneKitTrackerUpdateProcessed locked:_viewLocked deltaTime:_timeTracker.lastIntervalBetweenUpdates()];
        }
        else
        {
            NSLog(@"WARNING: did not update the player pose, because we could not get an update from the tracker.");
        }
    }
}

- (void)renderer:(id <SCNSceneRenderer>)aRenderer didSimulatePhysicsAtTime:(NSTimeInterval)time
{
    // Move SceneKit objects if their motion must be in sync with the tracker.
    
    _timeTracker.updateWithCurrentTime(time);
    
    // Handle touches events in the SceneKit thread.
    [self updateTouchesSceneKit];
 
    // Lock timing.
    NSTimeInterval timeDelta = _timeTracker.lastIntervalBetweenUpdates();

    // Shorter alias.
    TrackingErrorMessageState& state = _trackingErrorMessageState;
    
    // Too close
    state.timeSinceFirstTooCloseTrackingError += timeDelta;
    if (_slamState.lastSceneKitTrackerUpdateProcessed.trackerStatus == STTrackerStatusTooClose)
    {
        if (state.timeSinceLastTooCloseTrackingError != 0)
            state.timeSinceFirstTooCloseTrackingError = 0;
        state.timeSinceLastTooCloseTrackingError = 0;
        
        if (!self.lockHintView.hidden)
        {
            // Play voice over for view lock.
            [self readViewLock];
        }
    }
    else
    {
        state.timeSinceLastTooCloseTrackingError += timeDelta;
    }
    
    // Tracking is not reliable
    state.timeSinceFirstBadTrackingError += timeDelta;
    if (_slamState.lastSceneKitTrackerUpdateProcessed.trackerStatus == STTrackerStatusDodgyForUnknownReason)
    {
        if (state.timeSinceLastBadTrackingError != 0)
            state.timeSinceFirstBadTrackingError = 0;
        state.timeSinceLastBadTrackingError = 0;
    }
    else
    {
        state.timeSinceLastBadTrackingError += timeDelta;
    }
    
    // Handle tracking errors and lock status. We have to do this in the main thread since we need
    // to change UIKit elements.
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        // Lock hint feedback
        if (state.timeSinceLastTooCloseTrackingError > 0.4 &&
            !self.trackingLostLabel.hidden &&
            state.timeSinceFirstTooCloseTrackingError > 1.5)
        {
            [self.lockHintView setHidden:YES];
            [self hideTrackingLostMessage];
        }
    
        if (_slamState.lastSceneKitTrackerUpdateProcessed.trackerStatus != STTrackerStatusGood)
        {
            NSMutableAttributedString *attributedMessageText;
            
            if (_slamState.lastSceneKitTrackerUpdateProcessed.trackerStatus == STTrackerStatusTooClose)
            {
                SCNVector3 lookVector = [SCNTools getLookAtVectorOfNode:_gameData.player.pov];
                float angleToGround = [SCNTools angleBetweenVector:lookVector andVector:SCNVector3Make(0, -1, 0)];
                if (angleToGround < M_PI*45.0/180.0)
                {
                    // Looking at the ground
                    attributedMessageText = [self trackingMessageWithAttributedText:@"Too Close! Keep surfaces farther away." range:NSMakeRange(0, 11)];
                }
                else
                {
                    // Looking at a wall
                    attributedMessageText = [self trackingMessageWithAttributedText:@"Too Close! Hold a finger on the device to lock, and turn towards open space." range:NSMakeRange(0, 11)];
                    
                    [self.lockHintView setHidden:NO];
                }
                
                [self showTrackingLostMessage:attributedMessageText];
            }
            else
            {
                // Tracking totally lost
                if (state.timeSinceLastBadTrackingError == 0 && state.timeSinceFirstBadTrackingError > 0.4)
                {
                    attributedMessageText = [self trackingMessageWithAttributedText:@"Positional Tracking Lost! \rNot enough depth information." range:NSMakeRange(0, 25)];
                    [self showTrackingLostMessage:attributedMessageText];
                }
            }
        }

    });
    
    //-- Call into Game Category to update the player and other scenekit objects --//
    [self updateGameTimeSinceStart:_timeTracker.timeSinceStart()];
    [MotionLogs updateAtTime:_timeTracker.timeSinceStart()];
}

- (void)renderer:(id <SCNSceneRenderer>)aRenderer willRenderScene:(SCNScene *)scene atTime:(NSTimeInterval)time
{
    // If you try to move SceneKit objects here, you will have synchronization issues with the camera pose. It
    // is recommended to move objects earlier, in the didSimulatePhysicsAtTime callback.
}

#pragma mark - UI interactions

-(IBAction) actionButtonDown:(id)sender
{
    [_gameData.player actionButtonDown];
}

-(IBAction) warpButtonDown:(id)sender
{
    [_gameData.player warpButtonDown];
}

-(IBAction) warpButtonUp:(id)sender;
{
    [_gameData.player warpButtonUp];
}

- (IBAction)jumpToLabButtonPressed:(id)sender
{
    [self jumpToLab];
}

-(IBAction) actionButtonUp:(id)sender;
{
    [_gameData.player actionButtonUp];
}

- (IBAction)resetButtonPressed:(id)sender
{
    [self resetGameState];
}

// Make tracking messages prettier.
-(NSMutableAttributedString*) trackingMessageWithAttributedText:(NSString*)text range:(NSRange)range
{
    // iOS6 and above : Use NSAttributedStrings
    const CGFloat fontSize = 30.0;
    UIFont *lightFont = [UIFont fontWithName:@"OpenSans-Light" size:fontSize];
    UIFont *boldFont = [UIFont fontWithName:@"OpenSans-Semibold" size:fontSize];
    UIColor *foregroundColor = [UIColor yellowColor];
    
    // Create the attributes
    NSDictionary *attrs = @{NSFontAttributeName: lightFont,
                           NSForegroundColorAttributeName: foregroundColor};
    NSDictionary *subAttrs = @{NSFontAttributeName: boldFont};
    
    NSMutableAttributedString *attributedText =
    [[NSMutableAttributedString alloc] initWithString:text
                                           attributes:attrs];
    [attributedText setAttributes:subAttrs range:range];
    
    return attributedText;
}

- (void)showTrackingLostMessage:(NSMutableAttributedString*)attributedText
{
    self.trackingLostLabel.attributedText = attributedText;
    self.trackingLostLabel.hidden = NO;
}

- (void)hideTrackingLostMessage
{
    self.trackingLostLabel.hidden = YES;
}

- (IBAction)playMotionLogsButtonPressed:(id)sender
{
    [MotionLogs beginAtTime:_timeTracker.timeSinceStart()];
}

- (IBAction)recordButtonPressed:(id)sender
{
    //toggle recording
    if ([MotionLogs isRecording])
    {
        [MotionLogs stopMotionLogRecording];
        [_recordButton setTitle:@"Record Path" forState:UIControlStateNormal];
    }
    else
    {
        [MotionLogs startMotionLogRecording];
        [_recordButton setTitle:@"Stop Recording" forState:UIControlStateNormal];
    }
}
@end
