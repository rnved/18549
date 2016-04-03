/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <GLKit/GLKit.h>
#import <OpenGLES/ES2/glext.h> // GL_RED_EXT

#import "GraphicsRenderer.h"
#import "CustomShaders.h"

#import <Structure/StructureSLAM.h>
#import <ImageIO/ImageIO.h>

#define MAX_MESHES 30

// Local functions

void loadImageIntoTexture(NSString* nsName, NSString* type, GLuint *textureId)
{
    NSString * fileLocation = [[NSBundle mainBundle] pathForResource:nsName ofType:type];
    
    if(fileLocation == nil) {
        NSLog(@"Failed to load image %@ into texture %d!", nsName, *textureId); return;
    }
    
    CFURLRef srcURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                    (CFStringRef)fileLocation,
                                                    kCFURLPOSIXPathStyle, false);
    
    // Load Image ---------------------------------------
    
    CFStringRef keys[1] = { kCGImageSourceShouldCache }; // It's ambiguous what the default value is.
	CFTypeRef values[1] = { kCFBooleanFalse };           // So we explicitly set it to false.
	CFDictionaryRef optionsDict = CFDictionaryCreate(kCFAllocatorDefault, (const void **)keys, values, 1,
                                                     &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CGImageSourceRef imageSource = CGImageSourceCreateWithURL(srcURL, NULL);
    CGImageRef image = CGImageSourceCreateImageAtIndex(imageSource, 0, NULL);
    CFRelease(imageSource);
    CFRelease(optionsDict);
    CFRelease(srcURL);
    
    // ---------------------------------------------------
    
    // Calculate nearest power of 2 height which will fit the image.
	int w = (int)CGImageGetWidth(image), h = (int)CGImageGetHeight(image);
    
	CGDataProviderRef dataProvider = CGImageGetDataProvider(image);
	CFDataRef data = CGDataProviderCopyData(dataProvider);
    
    CGImageRelease(image);
    
    if(*textureId)
        glDeleteTextures(1, textureId);
    
    glGenTextures(1, textureId);
	glBindTexture(GL_TEXTURE_2D, *textureId);
    
    void * dataPtr = (void*)CFDataGetBytePtr(data);
    // On rare occasion texture is already power of 2, init directly:
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, dataPtr);
    
	CFRelease(data);
}

struct GraphicsRenderer::PrivateData
{
    XrayShader xRayShader;
    RGBATextureShader rgbaShader;
    
    NSString* lineTextureName;
    
    // the circle graphic texture
    GLuint lineTexture;
    
    // Texture unit to use for texture binding/rendering.
    GLenum textureUnit = GL_TEXTURE4;
};

GraphicsRenderer::GraphicsRenderer(NSString* lineTextureName)
: d (new PrivateData)
{
    d->lineTextureName = lineTextureName;
}

void GraphicsRenderer::initializeGL (GLenum defaultTextureUnit)
{
    d->textureUnit = defaultTextureUnit;
    
    glActiveTexture(d->textureUnit);
    loadImageIntoTexture([[d->lineTextureName lastPathComponent] stringByDeletingPathExtension],
                         [d->lineTextureName pathExtension], &d->lineTexture);
}

GraphicsRenderer::~GraphicsRenderer()
{
    if (d->lineTexture)
    {
        glDeleteTextures(1, &d->lineTexture);
        d->lineTexture = 0;
    }
}

void GraphicsRenderer::renderLine(const GLKVector3 pt1, const GLKVector3 pt2, const GLKMatrix4 &projectionMatrix, const GLKMatrix4 &modelViewMatrix, bool flipXY)
{
    glActiveTexture(d->textureUnit);
    glBindTexture(GL_TEXTURE_2D, d->lineTexture);
    
    d->rgbaShader.enable();
    d->rgbaShader.prepareRendering(projectionMatrix.m, modelViewMatrix.m, d->textureUnit);
    
    glEnableVertexAttribArray(CustomShader::ATTRIB_VERTEX);
    glEnableVertexAttribArray(CustomShader::ATTRIB_TEXCOORD);
    
    const float lineTextureAspectRatio = 8;
    float radius = 0.01;
    float ratio = 1.0/(radius*lineTextureAspectRatio*2);
    
    GLKVector3 direction = GLKVector3Subtract(pt2, pt1);
    float length = GLKVector3Length(direction);
    bool invertible;
    GLKVector3 camera = GLKMatrix4MultiplyVector3WithTranslation(GLKMatrix4Invert(modelViewMatrix, &invertible), GLKVector3Make(0, 0, 0));
    GLKVector3 directionToCamera = GLKVector3Subtract(camera, pt1);
    
    GLKVector3 perpendicularVec = GLKVector3CrossProduct(directionToCamera, direction);
    perpendicularVec = GLKVector3Normalize(perpendicularVec);
    
    GLKVector3 pts[4];
    pts[0] = GLKVector3Add(pt1, GLKVector3MultiplyScalar(perpendicularVec, radius));
    pts[1] = GLKVector3Subtract(pt1, GLKVector3MultiplyScalar(perpendicularVec, radius));
    pts[2] = GLKVector3Add(pt2, GLKVector3MultiplyScalar(perpendicularVec, radius));
    pts[3] = GLKVector3Subtract(pt2, GLKVector3MultiplyScalar(perpendicularVec, radius));
    
    GLKVector2 texcoord[4];
    if (flipXY)
    {
        texcoord[0] = GLKVector2Make(0, 0);
        texcoord[1] = GLKVector2Make(0, 1);
        texcoord[2] = GLKVector2Make(length*ratio, 0);
        texcoord[3] = GLKVector2Make(length*ratio, 1);
    }
    else
    {
        texcoord[0] = GLKVector2Make(length*ratio, 1);
        texcoord[1] = GLKVector2Make(length*ratio, 0);
        texcoord[2] = GLKVector2Make(0, 1);
        texcoord[3] = GLKVector2Make(0, 0);
    }
    glVertexAttribPointer(CustomShader::ATTRIB_VERTEX, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(GLfloat), pts);
    glVertexAttribPointer(CustomShader::ATTRIB_TEXCOORD, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), texcoord);
    
    glEnable(GL_DEPTH_TEST);
    glDisable(GL_BLEND);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    glDisable(GL_DEPTH_TEST);
    
    glDisableVertexAttribArray(CustomShader::ATTRIB_VERTEX);
    glDisableVertexAttribArray(CustomShader::ATTRIB_TEXCOORD);
}
