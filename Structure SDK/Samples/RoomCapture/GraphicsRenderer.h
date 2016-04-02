/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#pragma once

#import <GLKit/GLKit.h>
#import <CoreVideo/CVImageBuffer.h>

@class STMesh;

class GraphicsRenderer
{
public:
    GraphicsRenderer(NSString* lineTextureName);
    ~GraphicsRenderer();
    
    void initializeGL (GLenum defaultTextureUnit = GL_TEXTURE4);
    
    void renderLine(const GLKVector3 pt1, const GLKVector3 pt2, const GLKMatrix4& projectionMatrix, const GLKMatrix4& modelViewMatrix, bool flipXY);
    
private:
    
private:
    class PrivateData;
    PrivateData* d;
};
