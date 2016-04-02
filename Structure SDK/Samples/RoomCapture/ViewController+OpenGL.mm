/*
 This file is part of the Structure SDK.
 Copyright © 2015 Occipital, Inc. All rights reserved.
 http://structure.io
 */

#import "ViewController.h"
#import "ViewController+OpenGL.h"

#include <cmath>
#include <limits>

@implementation ViewController (OpenGL)

#pragma mark -  OpenGL

- (void)setupGL
{
    // Create an EAGLContext for our EAGLView.
    _display.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!_display.context) { NSLog(@"Failed to create ES context"); return; }
    
    [EAGLContext setCurrentContext:_display.context];
    [(EAGLView*)self.view setContext:_display.context];
    [(EAGLView*)self.view setFramebuffer];
    
    _display.yCbCrTextureShader = [[STGLTextureShaderYCbCr alloc] init];
    _display.rgbaTextureShader = [[STGLTextureShaderRGBA alloc] init];
    
    // Set up a textureCache for images output by the color camera.
    CVReturn texError = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _display.context, NULL, &_display.videoTextureCache);
    if (texError) { NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", texError); return; }
    
    // Scanning volume feedback.
    {
        // We configured the sensor for QVGA depth.
        const int w = 320, h = 240;
        
        // Create the RGBA buffer to store the feedback pixels.
        _display.scanningVolumeFeedbackBuffer.resize (w*h*4, 0);
        
        // Create the GL texture to display the feedback.
        glGenTextures(1, &_display.scanningVolumeFeedbackTexture);
        glBindTexture(GL_TEXTURE_2D, _display.scanningVolumeFeedbackTexture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    }
}

- (void)setupGLViewport
{
    const float vgaAspectRatio = 640.0f/480.0f;
    
    // Helper function to handle float precision issues.
    auto nearlyEqual = [] (float a, float b) { return std::abs(a-b) < std::numeric_limits<float>::epsilon(); };
    
    CGSize frameBufferSize = [(EAGLView*)self.view getFramebufferSize];
    
    float imageAspectRatio = 1.0f;
    
    float framebufferAspectRatio = frameBufferSize.width/frameBufferSize.height;
    
    // The iPad's diplay conveniently has a 4:3 aspect ratio just like our video feed.
    // Some iOS devices need to render to only a portion of the screen so that we don't distort
    // our RGB image. Alternatively, you could enlarge the viewport (losing visual information),
    // but fill the whole screen.
    if (!nearlyEqual (framebufferAspectRatio, vgaAspectRatio))
        imageAspectRatio = 480.f/640.0f;
    
    _display.viewport[0] = 0;
    _display.viewport[1] = 0;
    _display.viewport[2] = frameBufferSize.width*imageAspectRatio;
    _display.viewport[3] = frameBufferSize.height;
}

- (void)uploadGLColorTexture:(STColorFrame*)colorFrame
{
    _display.colorCameraGLProjectionMatrix = [colorFrame glProjectionMatrix];
    
    if (!_display.videoTextureCache)
    {
        NSLog(@"Cannot upload color texture: No texture cache is present.");
        return;
    }
    
    // Clear the previous color texture.
    if (_display.lumaTexture)
    {
        CFRelease (_display.lumaTexture);
        _display.lumaTexture = NULL;
    }
    
    // Clear the previous color texture.
    if (_display.chromaTexture)
    {
        CFRelease (_display.chromaTexture);
        _display.chromaTexture = NULL;
    }
    
    // Allow the texture cache to do internal cleanup.
    CVOpenGLESTextureCacheFlush(_display.videoTextureCache, 0);
    
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(colorFrame.sampleBuffer);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
    OSType pixelFormat = CVPixelBufferGetPixelFormatType (pixelBuffer);
    NSAssert(pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, @"YCbCr is expected!");
    
    // Activate the default texture unit.
    glActiveTexture (GL_TEXTURE0);
    
    // Create an new Y texture from the video texture cache.
    CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                _display.videoTextureCache,
                                                                pixelBuffer,
                                                                NULL,
                                                                GL_TEXTURE_2D,
                                                                GL_RED_EXT,
                                                                (int)width,
                                                                (int)height,
                                                                GL_RED_EXT,
                                                                GL_UNSIGNED_BYTE,
                                                                0,
                                                                &_display.lumaTexture);
    
    if (err)
    {
        NSLog(@"Error with CVOpenGLESTextureCacheCreateTextureFromImage: %d", err);
        return;
    }
    
    // Set good rendering properties for the new texture.
    glBindTexture(CVOpenGLESTextureGetTarget(_display.lumaTexture), CVOpenGLESTextureGetName(_display.lumaTexture));
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // Activate the default texture unit.
    glActiveTexture (GL_TEXTURE1);
    // Create an new CbCr texture from the video texture cache.
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       _display.videoTextureCache,
                                                       pixelBuffer,
                                                       NULL,
                                                       GL_TEXTURE_2D,
                                                       GL_RG_EXT,
                                                       (int)width/2,
                                                       (int)height/2,
                                                       GL_RG_EXT,
                                                       GL_UNSIGNED_BYTE,
                                                       1,
                                                       &_display.chromaTexture);
    if (err)
    {
        NSLog(@"Error with CVOpenGLESTextureCacheCreateTextureFromImage: %d", err);
        return;
    }
    
    glBindTexture(CVOpenGLESTextureGetTarget(_display.chromaTexture), CVOpenGLESTextureGetName(_display.chromaTexture));
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}

- (void)renderSceneWithDepthFrame:(STDepthFrame*)depthFrame colorFrame:(STColorFrame*)colorFrame
{
    // Activate our view framebuffer.
    [(EAGLView *)self.view setFramebuffer];
    
    glClearColor(0.0, 0.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glClear(GL_DEPTH_BUFFER_BIT);
    
    glViewport (_display.viewport[0], _display.viewport[1], _display.viewport[2], _display.viewport[3]);
    
    switch (_slamState.roomCaptureState)
    {
        case RoomCaptureStatePoseInitialization:
        {
            // Render the background image from the color camera.
            [self renderColorImage];
            
            // Render the feedback overlay to tell us if we are inside the scanning volume.
            [self renderScanningVolumeFeedbackOverlayWithDepthFrame:depthFrame colorFrame:colorFrame];
            
            break;
        }
            
        case RoomCaptureStateScanning:
        {
            // Render the background image from the color camera.
            [self renderColorImage];
            
            GLKMatrix4 depthCameraPose = [_slamState.tracker lastFrameCameraPose];
            GLKMatrix4 cameraGLProjection = _display.colorCameraGLProjectionMatrix;
            
            // In case we are not using registered depth.
            GLKMatrix4 colorCameraPoseInDepthCoordinateSpace;
            [depthFrame colorCameraPoseInDepthCoordinateFrame:colorCameraPoseInDepthCoordinateSpace.m];
            
            // colorCameraPoseInWorld
            GLKMatrix4 cameraViewpoint = GLKMatrix4Multiply(depthCameraPose, colorCameraPoseInDepthCoordinateSpace);
            
            // Render the current mesh reconstruction using the last estimated camera pose.
            [_slamState.scene renderMeshFromViewpoint:cameraViewpoint
                                   cameraGLProjection:cameraGLProjection
                                                alpha:1.0
                             highlightOutOfRangeDepth:false
                                            wireframe:true];
            
            break;
        }
            
            // MeshViewerController handles this.
        case RoomCaptureStateViewing:
        default: {}
    };
    
    // Check for OpenGL errors
    GLenum err = glGetError ();
    if (err != GL_NO_ERROR)
    {
        NSLog(@"glError: %d", err);
    }
    
    // Display the rendered framebuffer.
    [(EAGLView *)self.view presentFramebuffer];
}

- (void)renderColorImage
{
    if (!_display.lumaTexture || !_display.chromaTexture)
        return;
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(CVOpenGLESTextureGetTarget(_display.lumaTexture),
                  CVOpenGLESTextureGetName(_display.lumaTexture));
    
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(CVOpenGLESTextureGetTarget(_display.chromaTexture),
                  CVOpenGLESTextureGetName(_display.chromaTexture));
    
    glDisable(GL_BLEND);
    [_display.yCbCrTextureShader useShaderProgram];
    [_display.yCbCrTextureShader renderWithLumaTexture:GL_TEXTURE0 chromaTexture:GL_TEXTURE1];
    
    glUseProgram (0);
}


// If we are outside of the scanning volume we make the pixels very dark.
- (void)renderScanningVolumeFeedbackOverlayWithDepthFrame:(STDepthFrame*)depthFrame colorFrame:(STColorFrame*)colorFrame
{
    glActiveTexture(GL_TEXTURE2);
    
    glBindTexture(GL_TEXTURE_2D, _display.scanningVolumeFeedbackTexture);
    int cols = depthFrame.width, rows = depthFrame.height;
    
    // Get the list of depth pixels which lie within the scanning volume boundaries.
    std::vector<uint8_t> mask (rows*cols);
    [_slamState.cameraPoseInitializer detectInnerPixelsWithDepthFrame:[depthFrame registeredToColorFrame:colorFrame] mask:&mask[0]];
    
    // Fill the feedback RGBA buffer.
    for (int r = 0; r < rows; ++r)
        for (int c = 0; c < cols; ++c)
        {
            const int pixelIndex = r*cols + c;
            bool insideVolume = mask[pixelIndex];
            if (insideVolume)
            {
                // Set the alpha to 0, leaving the pixels already in the render buffer unchanged.
                _display.scanningVolumeFeedbackBuffer[4*pixelIndex+3] = 0;
            }
            else
            {
                // Set the alpha to a higher value, making the pixel in the render buffer darker.
                _display.scanningVolumeFeedbackBuffer[4*pixelIndex+3] = 200;
            }
        }
    
    // Upload the texture to the GPU.
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, cols, rows, GL_RGBA, GL_UNSIGNED_BYTE, _display.scanningVolumeFeedbackBuffer.data());
    
    // Rendering it with blending enabled to apply the overlay on the previously rendered buffer.
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    [_display.rgbaTextureShader useShaderProgram];
    [_display.rgbaTextureShader renderTexture:GL_TEXTURE2];
}

@end
