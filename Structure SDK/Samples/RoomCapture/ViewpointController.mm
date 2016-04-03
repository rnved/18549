/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "ViewpointController.h"

#import <mach/mach_time.h>

#import <algorithm>

// Helper functions
namespace
{
    double nowInSeconds()
    {
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        
        uint64_t newTime = mach_absolute_time();
        
        return ((double)newTime*timebase.numer)/((double)timebase.denom *1e9);
    }
}

GLKMatrix4 glProjectionMatrixFromPerspective(float fovXRadians, float aspectRatio)
{
    float yFOV = fovXRadians * 0.75;
    GLKMatrix4 proj = GLKMatrix4MakePerspective(yFOV, aspectRatio, 0.1, 25.0);

    // Switch from Structure SDK coordinate system to the OpenGL one.
    GLKMatrix4 flipYZ = GLKMatrix4MakeScale(1, -1, -1);
    return GLKMatrix4Multiply(proj, flipYZ);
}

struct ViewpointController::PrivateData
{
    // To determine the scale of the touch events.
    float screenSizeX = 0.0, screenSizeY = 0.0;
    
    double lastAnimationTimestamp = -1.0;
    
    bool isInTopViewMode = false;

    // 0 means 100% FPS mode, 1 means 100% in topview mode.
    float fpsModeToTopviewModeInterpolation = 0.0;
    
    bool cameraOrProjectionChangedSinceLastUpdate = false;
    
    // First Person Shooter (FPS) mode rotation velocity, comes from touch.
    GLKVector3 fpsRotationVelocity = GLKVector3Make (0, 0, 0);
    GLKVector3 fpsRotationVelocityDuringTouch = GLKVector3Make (0, 0, 0);
    
    // Top view translation velocity, comes from touch.
    GLKVector3 topviewTranslationVelocity             = GLKVector3Make (0, 0, 0);
    GLKVector3 topviewTranslation                     = GLKVector3Make (0, 0, 0);
    GLKVector3 topviewTranslationVelocityDuringTouch  = GLKVector3Make (0, 0, 0);
    
    // First Person Shooter (FPS) translation velocity, comes from Joystick
    GLKVector3 fpsTranslationVelocity = GLKVector3Make (0, 0, 0);
    GLKVector3 fpsTranslation         = GLKVector3Make (0, 0, 0);
    
    // Reduce the velocities at each step.
    GLKVector3 velocitiesDampingRatio = GLKVector3Make(0.75, 0.75, 0);

    GLKVector2 prevTouchPosition;
    NSTimeInterval prevTouchTimestamp;
    
    float previousTopviewRotationGestureValue = 0.0;

    float fovXRadiansWhenPinchGestureBegan;
    float fovXRadians;
    float aspectRatio;

    GLKMatrix4 glProjectionMatrix;
    
    // The camera orientation is restricted to a plane.
    float modelViewYaw;
    float modelViewPitch; // pitch is fixed in topview mode.
    
    // Set by the user, does not change during interactions.
    GLKVector3 referenceModelViewTranslation;
};

ViewpointController::ViewpointController(float screenSizeX, float screenSizeY)
: d (new PrivateData)
{
    d->screenSizeX = screenSizeX;
    d->screenSizeY = screenSizeY;
    reset();
}

ViewpointController::~ViewpointController()
{
    delete d; d = 0;
}

void ViewpointController::reset()
{
    d->isInTopViewMode = false;
    d->fpsModeToTopviewModeInterpolation = 0.0; // default is FPS mode
    
    d->fpsRotationVelocity = GLKVector3Make(0, 0, 0);
    d->topviewTranslationVelocity = GLKVector3Make(0, 0, 0);
    d->fpsTranslation = GLKVector3Make(0, 0, 0);
    d->fpsTranslationVelocity = GLKVector3Make(0, 0, 0);
    d->topviewTranslation = GLKVector3Make(0, 0, 0);
    
    d->cameraOrProjectionChangedSinceLastUpdate = false;
    
    d->lastAnimationTimestamp = nowInSeconds();
}

void ViewpointController::setCameraPerspective(float fovXRadians, float aspectRatio)
{
    d->fovXRadians = fovXRadians;
    d->aspectRatio = aspectRatio;
    d->glProjectionMatrix = glProjectionMatrixFromPerspective(fovXRadians, aspectRatio);
    d->cameraOrProjectionChangedSinceLastUpdate = true;
}

void ViewpointController::setCameraPose(GLKMatrix4 cameraPose)
{
    bool isInvertible = false;
    GLKMatrix4 modelView = GLKMatrix4Invert(cameraPose, &isInvertible);
    
    d->modelViewYaw = atan2f(-modelView.m02, sqrtf(modelView.m12*modelView.m12+modelView.m22*modelView.m22));
    d->modelViewPitch = atan2f(modelView.m12, modelView.m22);
    d->referenceModelViewTranslation = GLKVector3Make(modelView.m30, modelView.m31, modelView.m32);
    d->cameraOrProjectionChangedSinceLastUpdate = true;
}

void ViewpointController::setTopViewModeEnabled(bool enable)
{
    d->isInTopViewMode = enable;
}

void ViewpointController::onPinchGestureBegan(float scale)
{
    d->fovXRadiansWhenPinchGestureBegan = d->fovXRadians;
}

void ViewpointController::onPinchGestureChanged(float scale)
{
    const float maxFOV = M_PI * 0.9;
    const float minFOV = M_PI * 0.1;
    d->fovXRadians = MAX(minFOV, MIN(maxFOV, d->fovXRadiansWhenPinchGestureBegan / scale));
    d->glProjectionMatrix = glProjectionMatrixFromPerspective(d->fovXRadians, d->aspectRatio);
    d->cameraOrProjectionChangedSinceLastUpdate = true;
}

void ViewpointController::onRotationGestureBegan(float rotation)
{
    if(d->isInTopViewMode)
    {
        d->previousTopviewRotationGestureValue = rotation;
    }
}

void ViewpointController::onRotationGestureChanged(float rotation)
{
    if (d->isInTopViewMode)
    {
        float diffRotation = rotation - d->previousTopviewRotationGestureValue;
        GLKVector3 spinDegree = GLKVector3Make(diffRotation, 0, 0);
        updateTopviewRotationFromVelocity (spinDegree, 1);
        
        d->previousTopviewRotationGestureValue = rotation;
        d->cameraOrProjectionChangedSinceLastUpdate = true;
    }
}

// Rotation Gesture Control
void ViewpointController::onTouchBegan(GLKVector2 &touch, NSTimeInterval timestamp)
{
    // Stop any ongoing animation.
    d->fpsRotationVelocity = GLKVector3Make(0, 0, 0);
    
    d->prevTouchPosition = touch;
    d->prevTouchTimestamp = timestamp;
}

void ViewpointController::onTouchChanged(GLKVector2 &touch, NSTimeInterval timestamp)
{
    GLKVector2 distMoved = GLKVector2Subtract(touch, d->prevTouchPosition);
    if(d->isInTopViewMode)
    {
        // Top view, apply a translation.
        
        // Approximate the distance
        float xDistance = (cameraTopViewHeight - d->referenceModelViewTranslation.y) * d->fovXRadians;
        GLKVector3 panDist = GLKVector3Make(distMoved.x/d->screenSizeX*xDistance, 0, -distMoved.y/d->screenSizeX*xDistance);
        d->topviewTranslationVelocityDuringTouch = GLKVector3MultiplyScalar(panDist, 1.0/(timestamp - d->prevTouchTimestamp));
        
        updateTopViewTranslationFromVelocity(panDist, 1);
    }
    else
    {
        GLKVector3 spinDegree = GLKVector3Make(distMoved.x/d->screenSizeX * (d->fovXRadians), -distMoved.y/d->screenSizeY * d->fovXRadians * 0.75, 0);
        
        // Move faster than the actual degree for easier control
        spinDegree = GLKVector3MultiplyScalar(spinDegree, 1.5);
        
        updateFpsRotationFromVelocity(spinDegree, 1);
        
        // Estimate the rotation velocition to use it during animations afterwards.
        d->fpsRotationVelocityDuringTouch = GLKVector3MultiplyScalar(spinDegree, 1.0/(timestamp-d->prevTouchTimestamp));
    }
    
    d->cameraOrProjectionChangedSinceLastUpdate = true;
    
    d->prevTouchTimestamp = timestamp;
    d->prevTouchPosition = touch;
}

void ViewpointController::onTouchEnded(GLKVector2 &touch)
{
    if(d->isInTopViewMode)
    {
        d->topviewTranslationVelocity = d->topviewTranslationVelocityDuringTouch;
        d->topviewTranslationVelocityDuringTouch = GLKVector3Make(0, 0, 0);
    }
    else // FPS mode
    {
        d->fpsRotationVelocity = d->fpsRotationVelocityDuringTouch;
        d->fpsRotationVelocityDuringTouch = GLKVector3Make(0, 0, 0);
    }
}

// ModelView Matrix in OpenGL Space
GLKMatrix4 ViewpointController::currentGLModelViewMatrix() const
{
    // Interpolation between the translations in FPS and topview modes.
    GLKVector3 deltaTranslationInFpsMode = GLKVector3MultiplyScalar(d->fpsTranslation, 1.0-d->fpsModeToTopviewModeInterpolation);
    GLKVector3 deltaTranslationInTopviewMode = GLKVector3MultiplyScalar(d->topviewTranslation, d->fpsModeToTopviewModeInterpolation);
    
    GLKVector3 currentTranslation = GLKVector3Add(d->referenceModelViewTranslation,
                                                  GLKVector3Add (deltaTranslationInFpsMode, deltaTranslationInTopviewMode));
    
    GLKMatrix4 interpolatedTranslationMatrix = GLKMatrix4MakeTranslation(currentTranslation.x, currentTranslation.y, currentTranslation.z);
    
    GLKMatrix4 yawMatrix = GLKMatrix4MakeRotation(d->modelViewYaw, 0, 1, 0);
    GLKMatrix4 pitchMatrix = GLKMatrix4MakeRotation(d->modelViewPitch, 1, 0, 0);
    GLKMatrix4 fpsModelView =  GLKMatrix4Multiply( GLKMatrix4Multiply(pitchMatrix, yawMatrix), interpolatedTranslationMatrix);
    
    // Interpolation between the rotation in FPS and topview modes. Topview uses a M_PI/2 pitch.
    GLKMatrix4 revertFpsPitchMatrixForTopview = GLKMatrix4MakeRotation(-d->modelViewPitch * d->fpsModeToTopviewModeInterpolation, 1, 0, 0);
    GLKMatrix4 topViewPitchMatrix = GLKMatrix4MakeRotation(M_PI_2 * d->fpsModeToTopviewModeInterpolation, 1, 0, 0);
    
    // If fpsModeToTopviewModeInterpolation is 0, this matrix is identity, leaving the transform to the FPS mode.
    // If fpsModeToTopviewModeInterpolation is 1, this matrix reverses the FPS pitch, and applies the top view pitch and vertical translation.
    GLKMatrix4 fpsToTopviewTransform = GLKMatrix4MakeTranslation(0, 0, cameraTopViewHeight * d->fpsModeToTopviewModeInterpolation);
               fpsToTopviewTransform = GLKMatrix4Multiply(fpsToTopviewTransform, topViewPitchMatrix);
               fpsToTopviewTransform = GLKMatrix4Multiply(fpsToTopviewTransform, revertFpsPitchMatrixForTopview);
    
    return GLKMatrix4Multiply(fpsToTopviewTransform,fpsModelView);
}

// Projection Matrix in OpenGL Space
GLKMatrix4 ViewpointController::currentGLProjectionMatrix() const
{
    return d->glProjectionMatrix;
}

void ViewpointController::updateTopViewTranslationFromVelocity(GLKVector3 velocity, double elapsed)
{
    GLKVector3 diffVec = GLKVector3MultiplyScalar(velocity, elapsed);
    
    d->topviewTranslation.x -= diffVec.z * sin(d->modelViewYaw);
    d->topviewTranslation.z += diffVec.z * cos(d->modelViewYaw);
    
    d->topviewTranslation.x += diffVec.x * cos(d->modelViewYaw);
    d->topviewTranslation.z += diffVec.x * sin(d->modelViewYaw);
    
    d->topviewTranslation.x = MAX(-10.0, MIN(10.0, d->topviewTranslation.x));
    d->topviewTranslation.z = MAX(-10.0, MIN(10.0, d->topviewTranslation.z));
}

void ViewpointController::updateFpsTranslationFromVelocity(GLKVector3 velocity, double elapsed)
{
    GLKVector3 diffVec = GLKVector3MultiplyScalar(velocity, elapsed);
    
    d->fpsTranslation.x -= diffVec.z * sin(d->modelViewYaw);
    d->fpsTranslation.z += diffVec.z * cos(d->modelViewYaw);
    
    d->fpsTranslation.x += diffVec.x * cos(d->modelViewYaw);
    d->fpsTranslation.z += diffVec.x * sin(d->modelViewYaw);
    
    d->fpsTranslation.x = MAX(-10.0, MIN(10.0, d->fpsTranslation.x));
    d->fpsTranslation.z = MAX(-10.0, MIN(10.0, d->fpsTranslation.z));
}

void ViewpointController::updateTopviewRotationFromVelocity(GLKVector3 velocity, double elapsed)
{
    GLKVector3 spinVec = GLKVector3MultiplyScalar(velocity, elapsed);
    d->modelViewYaw += spinVec.x;
    // no pitch update in top view mode.
}

void ViewpointController::updateFpsRotationFromVelocity(GLKVector3 velocity, double elapsed)
{
    GLKVector3 spinVec = GLKVector3MultiplyScalar(velocity, elapsed);
    d->modelViewYaw += spinVec.x;
    d->modelViewPitch += spinVec.y;

    // Constrain the pitch and yaw to be in the range of [-pi, pi)
    d->modelViewYaw = d->modelViewYaw - 2*M_PI*floor(d->modelViewYaw/(2*M_PI)+0.5);
    d->modelViewPitch = d->modelViewPitch - 2*M_PI*floor(d->modelViewPitch/(2*M_PI)+0.5);

}

bool ViewpointController::update()
{
    double newTimestamp = nowInSeconds();
    double elapsed = newTimestamp - d->lastAnimationTimestamp;
    d->lastAnimationTimestamp = newTimestamp;
    
    bool currentViewpointChanged = d->cameraOrProjectionChangedSinceLastUpdate;
    
    // Apply first person shooter translation velocity.
    if (GLKVector3Length (d->fpsTranslationVelocity) > 1e-5f)
    {
        updateFpsTranslationFromVelocity(d->fpsTranslationVelocity, elapsed);
        currentViewpointChanged = true;
    }
    
    // Apply first person shooter rotation velocity.
    if(GLKVector3Length(d->fpsRotationVelocity) > 1e-5f)
    {
        updateFpsRotationFromVelocity(d->fpsRotationVelocity, elapsed);
        
        // Reduce the rotation speed over time.
        d->fpsRotationVelocity.x *= d->velocitiesDampingRatio.x;
        d->fpsRotationVelocity.y *= d->velocitiesDampingRatio.y;
        
        // Don't continue the animation for too long.
        if (fabs(d->fpsRotationVelocity.x) < 1e-3f) d->fpsRotationVelocity.x = 0;
        if (fabs(d->fpsRotationVelocity.y) < 1e-3f) d->fpsRotationVelocity.y = 0;
        currentViewpointChanged = true;
    }
    
    // Apply topview translation velocity.
    if(GLKVector3Length(d->topviewTranslationVelocity) > 1e-5f)
    {
        updateTopViewTranslationFromVelocity(d->topviewTranslationVelocity, elapsed);
        
        d->topviewTranslationVelocity.x *= d->velocitiesDampingRatio.x;
        d->topviewTranslationVelocity.z *= d->velocitiesDampingRatio.y;
        // Don't continue the animation for too long, one centimeter in top view is very small.
        if (fabs(d->topviewTranslationVelocity.x) < 1e-2f) d->topviewTranslationVelocity.x = 0;
        if (fabs(d->topviewTranslationVelocity.y) < 1e-2f) d->topviewTranslationVelocity.y = 0;
        currentViewpointChanged = true;
    }
    
    // Update the animation between first person shooter (fpsModeToTopviewModeInterpolation = 0)
    // and topview mode (fpsModeToTopviewModeInterpolation=1).
    if (d->isInTopViewMode)
    {
        // Progress toward topview.
        if(d->fpsModeToTopviewModeInterpolation < 1.0)
        {
            d->fpsModeToTopviewModeInterpolation += 0.02;
            d->fpsModeToTopviewModeInterpolation = fmin(d->fpsModeToTopviewModeInterpolation, 1.0);
            currentViewpointChanged = true;
        }
    }
    else
    {
        // Progress toward first person shooter.
        if(d->fpsModeToTopviewModeInterpolation > 0.0)
        {
            d->fpsModeToTopviewModeInterpolation -= 0.02;
            d->fpsModeToTopviewModeInterpolation = fmax(d->fpsModeToTopviewModeInterpolation, 0.0);
            currentViewpointChanged = true;
        }
    }
    
    d->cameraOrProjectionChangedSinceLastUpdate = false;
    
    return currentViewpointChanged;
}

void ViewpointController::processJoystickRadiusAndTheta(float radius, float theta)
{
    const float scale = 2.0;
    d->fpsTranslationVelocity.x = - scale * radius * cos(theta);
    d->fpsTranslationVelocity.y = 0;
    d->fpsTranslationVelocity.z = scale * radius * sin(theta);
}
