/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewController+Touch.h"
#import "ViewController+Game.h"
#import "SCNTools.h"

#import "GameData.h"

#pragma mark - UITouchExt wrapper

enum class GestureType
{
    Unknown = 0,
    Pan,
    Spurious, // will be ignored
};

// A wrapper for UITouch.
struct UITouchExt
{
    UITouch *touch;
    CGPoint startPoint;
    CGPoint currentPoint;
    GestureType gestureType;
    bool processed;
    
    UITouchExt(UITouch *newTouch, CGPoint newStartPoint)
    {
        touch = newTouch;
        startPoint = newStartPoint;
        currentPoint = newStartPoint;
        gestureType = GestureType::Unknown;
        processed = false;
    }
    
    void update (CGPoint newCurrentPoint)
    {
        currentPoint = newCurrentPoint;
    }
};

#pragma mark - ViewController+Touch

@implementation ViewController (Touch)

NSMutableArray *trackedTouches;
CGPoint previousPositionSingle;
NSTimeInterval previousPanTime;
float previousPanRate;

- (void)setupGestures;
{
    [self.view setMultipleTouchEnabled:YES];
    trackedTouches = [[NSMutableArray alloc] init];
}

- (BOOL)existsTouchOfType:(GestureType)touchType
{
    int i = 0;
    while (i < trackedTouches.count)
    {
        UITouchExt *_touchExt = (UITouchExt*)[trackedTouches[i] pointerValue];
        if (_touchExt->gestureType == touchType)
            return YES;
        i++;
    }
    return NO;
}

- (UITouchExt*)getTouchExt:(UITouch *)touch
{
    int i = 0;
    while (i < trackedTouches.count)
    {
        UITouchExt *_touchExt = (UITouchExt*)[trackedTouches[i] pointerValue];
        if (touch == _touchExt->touch)
            return _touchExt;
        else
            i++;
    }
    return nil;
}

#pragma mark - individual touch event handling

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches)
    {
        UITouchExt *touchExt = new UITouchExt(touch, [touch locationInView:self.view]);
        [trackedTouches addObject:[NSValue valueWithPointer:touchExt]];
    }
    [self updateTouchPanLockUI];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches)
    {
        UITouchExt *touchExt = [self getTouchExt:touch];
        if (touchExt)
        {
            touchExt->update([touch locationInView:self.view]);
            touchExt->processed = NO;
        }
    }
    [self updateTouchPanLockUI];
}

- (void)removeTouches:(NSSet *)touches
{
    for (UITouch *touch in touches)
    {
        int i = 0;
        while (i < trackedTouches.count)
        {
            UITouchExt *_touchExt = (UITouchExt*)[trackedTouches[i] pointerValue];
            if (touch == _touchExt->touch)
                [trackedTouches removeObjectAtIndex:i];
            else
                i++;
        }
    }
    [self updateTouchPanLockUI];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches)
    {
        UITouchExt *touchExt = [self getTouchExt:touch];
        if (touchExt)
            touchExt->update([touch locationInView:self.view]);
    }
    [self removeTouches:touches];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self removeTouches:touches];
}

#pragma mark - touch update logic

- (void)updateTouchPanLockUI
{
    if ((trackedTouches.count == 0) != self.lockPanView.hidden)
    {
        self.lockPanView.hidden = (trackedTouches.count == 0);
    }
}

- (void)updateTouchesSceneKit
{
    _viewLocked = trackedTouches.count > 0;
    
    //Pan Inertia
    if (!_viewLocked)
    {
        if (fabs(previousPanRate) > 0.005)
        {
            previousPanRate *= 0.9;
            
            SCNNode *panRotationNode = _gameData.player.panRotationNode;
            GLKMatrix4 pose = SCNMatrix4ToGLKMatrix4(panRotationNode.transform);
            GLKMatrix4 dR = GLKMatrix4MakeRotation (previousPanRate, 0, 1, 0);
            GLKMatrix4 newPose = GLKMatrix4Multiply (dR, pose);
            panRotationNode.transform = SCNMatrix4FromGLKMatrix4(newPose);
        }
        else
        {
            previousPanRate = 0;
        }
    }
    
    //Pan Gesture
    int i = 0;
    while (i < trackedTouches.count)
    {
        UITouchExt *_touchExt = (UITouchExt*)[trackedTouches[i] pointerValue];
        
        if (_touchExt->processed)
        {
            i++; continue;
        }
        
        //identifying the gesture.
        if (_touchExt->gestureType == GestureType::Unknown)
        {
            if(![self existsTouchOfType:GestureType::Pan])
            {
                _touchExt->gestureType = GestureType::Pan;
                previousPositionSingle = _touchExt->currentPoint;
            }
            else
            {
                _touchExt->gestureType = GestureType::Spurious;
            }
        }
        
        //touch interaction behaviour
        if (_touchExt->gestureType == GestureType::Pan)
        {
            [self handlePanSinglePoint:_touchExt->currentPoint];
        }
        
        _touchExt->processed = YES;
        i++;
    }
}

- (void) handlePanSinglePoint:(CGPoint)currentTouchPoint
{
    // We turn a 2D pan gesture into a single-axis rotation around the vertical in 3D SceneKit space (y)
    // a touch gesture in the X direction will rotate around the upVector
    // a touch gesture in the Y direction will rotate around the rightVector
    
    GLfloat distMovedX = currentTouchPoint.x - previousPositionSingle.x;
    GLfloat distMovedY = currentTouchPoint.y - previousPositionSingle.y;
    
    SCNNode *panRotationNode = _gameData.player.panRotationNode;
    SCNNode *povCamera = _gameData.player.pov;
    
    SCNMatrix4 povCameraRotationMatrix = [SCNTools isolateRotationFromSCNMatrix4:povCamera.worldTransform];
    
    SCNVector3 upVectorRotated = [SCNTools multiplyVector:SCNVector3Make(0, 1, 0) bySCNMatrix4:povCameraRotationMatrix];
    SCNVector3 rightVectorRotated = [SCNTools multiplyVector:SCNVector3Make(1, 0, 0) bySCNMatrix4:povCameraRotationMatrix];
    float rotationAmount = distMovedX*upVectorRotated.y + distMovedY*rightVectorRotated.y;
    // An arbitrary relative rate of rotation, scaled based on screen size.
    float rY = rotationAmount/(_gameData.view.window.bounds.size.width*0.3);
    
    GLKMatrix4 pose = SCNMatrix4ToGLKMatrix4(panRotationNode.transform);
    GLKMatrix4 dR = GLKMatrix4MakeRotation (rY, 0, 1, 0);
    GLKMatrix4 newPose = GLKMatrix4Multiply (dR, pose);
    panRotationNode.transform = SCNMatrix4FromGLKMatrix4(newPose);
    
    previousPositionSingle = currentTouchPoint;
    previousPanRate = rY;
}
@end
