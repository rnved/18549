/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#pragma once

#import <UIKit/UIKit.h>
#import <SceneKit/SceneKit.h>

#import <Structure/StructureSLAM.h>

#import "StructureStatusUI/StructureStatusUI.h"

#import "GameData.h"
#import "TrackerThread.h"

// SLAM-related members.
struct SlamData
{
    // Will set ISO automatically, but will force exposure to targetExposureTimeInSeconds.
    const bool useManualExposureAndAutoISO = true;
    
    // Reducing the exposure time by half helps getting a more accurate tracking by reducing motion
    // blur and rolling shutter. A multiple of 60Hz is best for countries using a 60Hz electric
    // current (e.g North America), since it would be in sync with potential light periods.
    //
    // If you observe tracking unstabilities when looking at scenes with little texture, you may
    // want to set it to 1./50. if you are in a country using 50Hz current, e.g. in Europe.
    const double targetExposureTimeInSeconds = 1./60.;
    
    STStreamConfig structureStreamConfig = STStreamConfigDepth320x240;
    
    // The tracker starts at a "normal" human height, ~1.5 meters. This will be adjusted later
    // on if we see the ground.
    GLKVector4 initialTrackerTranslation = GLKVector4Make (0, -1.5, 0, 1);
    
    bool initialized = false;
    bool shouldResetPose = true;
    bool isTracking = false;
    
    STScene *scene = nil;
    STCameraPoseInitializer *cameraPoseInitializer = nil;
    
    TrackerUpdate lastSceneKitTrackerUpdateProcessed;
    
    TrackerThread* trackerThread = nil;
    
    // OpenGL context.
    EAGLContext *context = nil;
    
    double previousFrameTimestamp = -1.0;
};

/*
 Through vigorous playtesting, we've found that many people need to be initially guided
 to understand how to move and manipulate objects in Unbounded Tracking.
 
 We do this in released app S.T.A.R. OPS, and we leave it here in case you want to use
 it in your application.
 
 The most important thing your users need to intuit is that they can actually walk, like,
 in the real world, and their motion is tracked. So, we initially disable and remove the
 grab and warp UI buttons until the user goes through 3 steps:
 
 1. Walking onto a pressure switch, making a box drop
 
 2. Grabbing the box, by pointing at it and holding down the right thumb button.
 
 3. Carrying the box over to another pressure switch.
 
 If you want to skip these steps, you will want to initially set the tutorial stage to
 TUT_FINISHED.
*/
enum class TutorialStage
{
    NotStarted = 0,
    
    NeedToWalkOnFloorButton,  // suggesting to the user to walk to the first button

    NeedToGrabFirstCube, // suggesting to the user to grab a block

    NeedToDropCubeOnButton, // suggesting to the user to drop the block on the second button
    
    NeedToTryWarp, //suggesting to the user to use warp to get to the next room

    Finished // Can go to the next room, free roam time
};

// Helper class to manage the delta between this frame and previous ones
class TimeTracker
{
public:
    void updateWithCurrentTime(NSTimeInterval time)
    {
        if (!hasPreviousTime)
        {
            hasPreviousTime = true;
        }
        else
        {
            _lastIntervalBetweenUpdates = time - previousUpdateTime;
        }
        
        previousUpdateTime = time;
        
        if (!hasStartTime)
        {
            hasStartTime = true;
            startTime = time;
        }
    }
    
    double lastIntervalBetweenUpdates() const { return _lastIntervalBetweenUpdates; }
    
    double timeSinceStart() const { return (previousUpdateTime - startTime); }
    
private:
    NSTimeInterval startTime = 0.;
    bool hasStartTime = false;
    
    NSTimeInterval previousUpdateTime = 0.;
    bool hasPreviousTime = false;
    
    double _lastIntervalBetweenUpdates = 1/30.0;
};

@interface ViewController : UIViewController <SCNSceneRendererDelegate>
{
    //Data for Structure Sensor + SLAM
    SlamData _slamState;
    STSensorController *_sensorController;
    StructureStatusUI *_structureStatusUI;
    // Color Capture Handles
    AVCaptureSession *_avCaptureSession;
    AVCaptureDevice *_videoDevice;
    // IMU data.
    CMMotionManager *_motionManager;
    NSOperationQueue *_imuQueue;
    GLKVector3 _lastGravity;
    
    //Game-specific
    TimeTracker _timeTracker;
    bool _viewLocked;
    TutorialStage _tutorialStage; // Game tutorial stage.
    GameData* _gameData;
    
    // Set so reset can be performed in the SceneKit thread
    bool _needsFullGameStateReset;
}

// UI
@property (weak, nonatomic) IBOutlet UIView *reticleView;
@property (weak, nonatomic) IBOutlet UIView *lockHintView;
@property (weak, nonatomic) IBOutlet UIView *lockPanView;
@property (weak, nonatomic) IBOutlet UILabel *trackingLostLabel;
@property (weak, nonatomic) IBOutlet UIImageView *lockHintImage;
@property (weak, nonatomic) IBOutlet UILabel *missionLabel;
@property (weak, nonatomic) IBOutlet UIButton *actionButton;
@property (weak, nonatomic) IBOutlet UIButton *warpButton;
- (IBAction)resetButtonPressed:(id)sender;
- (IBAction)actionButtonDown:(id)sender;
- (IBAction)actionButtonUp:(id)sender;
- (IBAction)warpButtonDown:(id)sender;
- (IBAction)warpButtonUp:(id)sender;


@property (weak, nonatomic) IBOutlet UIButton *playMotionLogsButton;
@property (weak, nonatomic) IBOutlet UIButton *recordButton;
- (IBAction)playMotionLogsButtonPressed:(id)sender;
- (IBAction)jumpToLabButtonPressed:(id)sender;
@end
