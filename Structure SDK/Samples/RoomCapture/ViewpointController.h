/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#pragma once

#import <GLKit/GLKit.h>

// Return a projection matrix in Structure SDK coordinate space (X right, Y down, Z forward).
GLKMatrix4 glProjectionMatrixFromPerspective(float fovXRadians, float aspect);

class ViewpointController
{
public:
    const float cameraTopViewHeight = 6.0; // meters
    
public:
    ViewpointController(float screenSizeX, float screenSizeY);
    ~ViewpointController();
    
    void reset();

    // Apply one update step. Will apply current velocities and animations.
    // Returns true if the current viewpoint changed.
    bool update();
    
    // Set the virtual viewpoint perspective from an¡ given horizontal field of view angle and aspect ratio.
    void setCameraPerspective(float fovXRadians, float aspect);
    
    // Set the virtual viewpoint position and orientation.
    void setCameraPose(GLKMatrix4 pose);

    // Current modelView matrix in OpenGL coordinate Space
    GLKMatrix4 currentGLModelViewMatrix() const;
    
    // Current projection matrix in OpenGL coordinateSpace
    GLKMatrix4 currentGLProjectionMatrix() const;
    
    // Activate or desactivate the top view mode (bird-eye).
    void setTopViewModeEnabled (bool enabled);

    // Pinch scale gesture will adjust the field of view
    void onPinchGestureBegan(float scale);
    void onPinchGestureChanged(float scale);
    
    // Rotation gesture will control the in-plane 2D rotation in topview mode.
    void onRotationGestureBegan(float rotation);
    void onRotationGestureChanged(float rotation);
    
    // Default finger touch controls 3D Rotation in FPS mode, and 2D translation in topview mode.
    void onTouchBegan(GLKVector2 &touch, NSTimeInterval timestamp);
    void onTouchChanged(GLKVector2 &touch, NSTimeInterval timestamp);
    void onTouchEnded(GLKVector2 &touch);
    
    // Will control the translation velocity in FPS mode.
    void processJoystickRadiusAndTheta(float radius, float theta);
    
private:
    void updateTopViewTranslationFromVelocity(GLKVector3 velocity, double elapsed);
    void updateTopviewRotationFromVelocity(GLKVector3 velocity, double elapsed);
    
    void updateFpsTranslationFromVelocity(GLKVector3 velocity, double elapsed);
    void updateFpsRotationFromVelocity (GLKVector3 velocity, double elapsed);
    
private:
    class PrivateData;
    PrivateData* d;
};
