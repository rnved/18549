/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "TrackerThread.h"

struct TrackerCommand
{
    enum Action
    {
        ActionNone,
        ActionReset,
        ActionSetInitialPose,
        ActionProcessNextFrame
    };
    
    bool finished () const { return action == ActionNone || isProcessed; }
    
    Action action = ActionNone;
    
    // For TrackerCommandProcessNextFrame command
    STDepthFrame* depthFrame;
    STColorFrame* colorFrame;
    
    // For setInitialPose command.
    GLKMatrix4 cameraPose;
    
    double timestamp = -1.;
    
    bool isProcessed = false;
};

@interface TrackerThread ()
{
    STTracker* _tracker;

    NSThread* _trackerThread;

    TrackerCommand _nextCommand;
    NSCondition* _nextCommandChangedCondition;
    
    TrackerUpdate _lastUpdate;
    NSCondition* _lastUpdateChangedCondition;
}

-(void) threadMain;
-(void)estimateNewPose:(const TrackerCommand&)command;
@end

@implementation TrackerThread

-(id)init
{
    self = [super init];
    if (self)
    {
        _nextCommandChangedCondition = [[NSCondition alloc] init];
        _lastUpdateChangedCondition = [[NSCondition alloc] init];
        _trackerThread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMain) object:nil];
    }
    return self;
}

-(void)dealloc
{
    [self stop];
}

-(TrackerUpdate)lastUpdate
{
    [_lastUpdateChangedCondition lock];
    TrackerUpdate lastUpdateCopy = _lastUpdate;
    [_lastUpdateChangedCondition unlock];
    return lastUpdateCopy;
}

-(STTracker*)tracker
{
    return _tracker;
}

-(void)setTracker:(STTracker *)newTracker
{
    bool wasRunning = _trackerThread.isExecuting;
    
    if (wasRunning)
        [self stop];
    
    _tracker = newTracker;
    
    if (newTracker != nil && wasRunning)
        [self start];
}

-(double) threadPriority
{
    return _trackerThread.threadPriority;
}

-(void) setThreadPriority:(double)threadPriority
{
    _trackerThread.threadPriority = threadPriority;
}

-(void) start
{
    if (_trackerThread.isExecuting)
    {
        return;
    }
    
    [_trackerThread start];
    
    // We could use a condition here. We just want to wait until the thread finished.
    while (!_trackerThread.isExecuting)
        [NSThread sleepForTimeInterval:0.005]; // sleep for 5 ms.
}

-(void) stop
{
    [_trackerThread cancel];
    
    {
        [_nextCommandChangedCondition lock];
        _nextCommand.action = TrackerCommand::ActionNone;
        [_nextCommandChangedCondition signal];
        [_nextCommandChangedCondition unlock];
    }
    
    if (_trackerThread.isFinished)
        return;
    
    // We could use a condition here. We just want to wait until the thread finished.
    while (!_trackerThread.isFinished)
        [NSThread sleepForTimeInterval:0.005]; // sleep for 5 ms.
}

-(void) reset
{
    [_nextCommandChangedCondition lock];
    while (!_nextCommand.finished())
        [_nextCommandChangedCondition wait];
    
    _nextCommand = TrackerCommand ();
    _nextCommand.action = TrackerCommand::ActionReset;
    [_nextCommandChangedCondition signal];
    
    [_nextCommandChangedCondition unlock];
}

-(void) setInitialTrackerPose:(GLKMatrix4)newPose timestamp:(double)timestamp
{
    [_nextCommandChangedCondition lock];
    
    // Make sure the previous frame is processed.
    while (!_nextCommand.finished())
        [_nextCommandChangedCondition wait];
    
    _nextCommand.action = TrackerCommand::ActionSetInitialPose;
    _nextCommand.cameraPose = newPose;
    _nextCommand.isProcessed = false;
    _nextCommand.depthFrame = nil;
    _nextCommand.colorFrame = nil;
    _nextCommand.timestamp = timestamp;
    
    [_nextCommandChangedCondition signal];
    [_nextCommandChangedCondition unlock];
}

-(void) updateWithMotion:(CMDeviceMotion*)motion
{
    // CoreMotion updates are thread safe in STTracker.
    [_tracker updateCameraPoseWithMotion:motion];
}

-(bool) updateWithDepthFrame:(STDepthFrame*)depthFrame colorFrame:(STColorFrame*)colorFrame maxWaitTimeSeconds:(double)waitTime
{
    [_nextCommandChangedCondition lock];
    
    // Make sure the previous frame is processed.
    {
        NSDate* timeoutDate = [NSDate dateWithTimeIntervalSinceNow:waitTime];
        bool didTimeout = false;
        while (!didTimeout && !_nextCommand.finished())
        {
            didTimeout = ([_nextCommandChangedCondition waitUntilDate:timeoutDate] == NO);
        }
        
        if (didTimeout)
        {
            [_nextCommandChangedCondition unlock];
            return false;
        }
    }
    
    _nextCommand.action = TrackerCommand::ActionProcessNextFrame;
    _nextCommand.isProcessed = false;
    _nextCommand.timestamp = depthFrame.timestamp;
    _nextCommand.depthFrame = [depthFrame copy];
    _nextCommand.colorFrame = colorFrame;
    
    [_nextCommandChangedCondition signal];
    [_nextCommandChangedCondition unlock];
    return true;
}

-(TrackerUpdate) waitForUpdateMoreRecentThan:(NSTimeInterval)timestamp maxWaitTimeSeconds:(double)waitTime
{
    [_lastUpdateChangedCondition lock];

    {
        NSDate* timeoutDate = [NSDate dateWithTimeIntervalSinceNow:waitTime];
        bool didTimeout = false;
        while (!didTimeout && _lastUpdate.timestamp < (timestamp + 1e-7))
        {
            didTimeout = ([_lastUpdateChangedCondition waitUntilDate:timeoutDate] == NO);
        }
    }

    TrackerUpdate lastUpdateCopy = _lastUpdate;
    [_lastUpdateChangedCondition unlock];
    
    return lastUpdateCopy;
}

-(void) threadMain
{
    while (!_trackerThread.cancelled)
    {
        // We need an autoreleasepool to capture autorelease objects, otherwise they won't be
        // garbage collected before the thread exits.
        @autoreleasepool
        {
            [_nextCommandChangedCondition lock];
            
            if (_nextCommand.finished())
                [_nextCommandChangedCondition wait];
            
            TrackerCommand currentCommand = _nextCommand;
            
            _nextCommand = TrackerCommand(); // make sure we don't keep handles on sample buffers, etc.
            _nextCommand.isProcessed = true;
            [_nextCommandChangedCondition signal];
            [_nextCommandChangedCondition unlock];
            
            // Nothing to process? Let's wait for the next command.
            if (currentCommand.isProcessed)
            {
                continue;
            }
            
            switch (currentCommand.action)
            {
                case TrackerCommand::ActionNone:
                {
                    break;
                }
                    
                case TrackerCommand::ActionReset:
                {
                    [_tracker reset];
                    {
                        [_lastUpdateChangedCondition lock];
                        _lastUpdate = TrackerUpdate();
                        [_lastUpdateChangedCondition signal];
                        [_lastUpdateChangedCondition unlock];
                    }
                    break;
                }
                    
                case TrackerCommand::ActionSetInitialPose:
                {
                    _tracker.initialCameraPose = currentCommand.cameraPose;
                    {
                        [_lastUpdateChangedCondition lock];
                        
                        _lastUpdate = TrackerUpdate();
                        _lastUpdate.cameraPose = currentCommand.cameraPose;
                        _lastUpdate.timestamp = currentCommand.timestamp;
                        _lastUpdate.couldEstimatePose = true;
                        _lastUpdate.trackerStatus = STTrackerStatusGood;
                        _lastUpdate.trackingError = nil;
                        
                        [_lastUpdateChangedCondition signal];
                        [_lastUpdateChangedCondition unlock];
                    }
                    break;
                }
                    
                case TrackerCommand::ActionProcessNextFrame:
                {
                    [self estimateNewPose:currentCommand];
                    if (currentCommand.colorFrame)
                        currentCommand.colorFrame = nil;
                    if (currentCommand.depthFrame)
                        currentCommand.depthFrame = nil;
                    break;
                }
                    
                default:
                    break;
            };
            
            currentCommand.isProcessed = true;
        }
    } // autoreleasepool
}

-(void) estimateNewPose:(const TrackerCommand&)command
{
    NSError* trackerError = nil;
    
    TrackerUpdate newTrackerUpdate;
    newTrackerUpdate.timestamp = command.depthFrame.timestamp;
    
    // First try to estimate the 3D pose of the new frame.
    bool trackingOk = [_tracker updateCameraPoseWithDepthFrame:command.depthFrame
                                                    colorFrame:command.colorFrame
                                                         error:&trackerError];
    
    newTrackerUpdate.trackerStatus = _tracker.status;
    newTrackerUpdate.trackingError = trackerError;
    
    // When the quality was poor, we could still get a pose.
    newTrackerUpdate.couldEstimatePose = trackingOk || trackerError.code == STErrorTrackerPoorQuality;
    
    if (newTrackerUpdate.couldEstimatePose)
        newTrackerUpdate.cameraPose = _tracker.lastFrameCameraPose;
    
    {
        [_lastUpdateChangedCondition lock];
        _lastUpdate = newTrackerUpdate;
        [_lastUpdateChangedCondition signal];
        [_lastUpdateChangedCondition unlock];
    }
}

@end // TrackerThread
