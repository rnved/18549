/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "MeshViewController.h"
#import "MeshRenderer.h"
#import "GraphicsRenderer.h"
#import "ViewpointController.h"
#import "Joystick.h"
#import "CustomUIKitStyles.h"

#import <ImageIO/ImageIO.h>

#include <vector>

// Local Helper Functions
namespace
{
    
    void saveJpegFromRGBABuffer(const char* filename, unsigned char* src_buffer, int width, int height)
    {
        FILE *file = fopen(filename, "w");
        if(!file)
            return;
        
        CGColorSpaceRef colorSpace;
        CGImageAlphaInfo alphaInfo;
        CGContextRef context;
        
        colorSpace = CGColorSpaceCreateDeviceRGB();
        alphaInfo = kCGImageAlphaNoneSkipLast;
        context = CGBitmapContextCreate(src_buffer, width, height, 8, width * 4, colorSpace, alphaInfo);
        CGImageRef rgbImage = CGBitmapContextCreateImage(context);
        
        CGContextRelease(context);
        CGColorSpaceRelease(colorSpace);
        
        CFMutableDataRef jpgData = CFDataCreateMutable(NULL, 0);
        
        CGImageDestinationRef imageDest = CGImageDestinationCreateWithData(jpgData, CFSTR("public.jpeg"), 1, NULL);
        CFDictionaryRef options = CFDictionaryCreate(kCFAllocatorDefault, // our empty IOSurface properties dictionary
                                                     NULL,
                                                     NULL,
                                                     0,
                                                     &kCFTypeDictionaryKeyCallBacks,
                                                     &kCFTypeDictionaryValueCallBacks);
        CGImageDestinationAddImage(imageDest, rgbImage, (CFDictionaryRef)options);
        CGImageDestinationFinalize(imageDest);
        CFRelease(imageDest);
        CFRelease(options);
        CGImageRelease(rgbImage);
        
        fwrite(CFDataGetBytePtr(jpgData), 1, CFDataGetLength(jpgData), file);
        fclose(file);
        CFRelease(jpgData);
    }
    
}

enum MeasurementState {
    Measurement_Clear,
    Measurement_Point1,
    Measurement_Point2,
    Measurement_Done
};

@interface MeshViewController ()
{
    CADisplayLink *_displayLink;
    MeshRenderer *_meshRenderer;
    GraphicsRenderer *_graphicsRenderer;
    ViewpointController *_viewpointController;
    GLfloat _glViewport[4];
    
    Joystick *_translationJoystick;
    
    GLKMatrix4 _cameraPoseBeforeUserInteractions;
    float _cameraFovBeforeUserInteractions;
    float _cameraAspectRatioBeforeUserInteractions;

    UILabel *_rulerText;
    UIImageView * _circle1;
    UIImageView * _circle2;
    
    MeasurementState _measurementState;
    GLKVector3 _pt1;
    GLKVector3 _pt2;
}

@property STMesh *meshRef;

@property MFMailComposeViewController *mailViewController;

@end

#pragma mark - Initialization

@implementation MeshViewController

- (id)initWithNibName:(NSString *)nibNameOrNil
               bundle:(NSBundle *)nibBundleOrNil
{
    // Initialize C++ members.
    _meshRenderer = 0;
    _graphicsRenderer = 0;
    _viewpointController = 0;
    
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self)
    {
        UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithTitle:@"Back"
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(dismissView)];
        
        self.navigationItem.leftBarButtonItem = backButton;
        
        UIBarButtonItem *emailButton = [[UIBarButtonItem alloc] initWithTitle:@"Email"
                                                                        style:UIBarButtonItemStylePlain
                                                                       target:self
                                                                       action:@selector(emailMesh)];
        self.navigationItem.rightBarButtonItem = emailButton;
        
        
        self.title = @"Structure Sensor Room Capture";
        
        // Initialize Joystick.
        const float joystickFrameSize = self.view.frame.size.height * 0.4;
        CGRect joystickFrame = CGRectMake(0, self.view.frame.size.height-joystickFrameSize,joystickFrameSize,joystickFrameSize);
        _translationJoystick = [[Joystick alloc] initWithFrame:joystickFrame
                                               backgroundImage:@"outerCircle.png"
                                                 joystickImage:@"innerCircle.png"];
        [self.view addSubview:_translationJoystick.view];
        
        [self.measurementButton applyCustomStyleWithBackgroundColor:blueButtonColorWithAlpha];
        [self.measurementGuideLabel applyCustomStyleWithBackgroundColor:blackLabelColorWithLightAlpha];
        
        _rulerText = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 100, 40)];
        [_rulerText applyCustomStyleWithBackgroundColor:blackLabelColorWithAlpha];

        _rulerText.textAlignment = NSTextAlignmentCenter;
        [self.view addSubview:_rulerText];
        [self.view sendSubviewToBack:_rulerText];
        
        _circle1 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"innerCircle.png"]];
        _circle2 = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"innerCircle.png"]];
        
        CGRect frame = _circle1.frame;
        frame.size = CGSizeMake(50, 50);
        _circle1.frame = frame;
        _circle2.frame = frame;
        
        [self.view addSubview:_circle1];
        [self.view addSubview:_circle2];
        [self.view sendSubviewToBack:_circle1];
        [self.view sendSubviewToBack:_circle2];
        
    }
    
    return self;
}

-(void)dealloc
{
    delete _meshRenderer; _meshRenderer = 0;
    delete _graphicsRenderer; _graphicsRenderer = 0;
    delete _viewpointController; _viewpointController = 0;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.meshViewerMessageLabel.alpha = 0.0;
    self.meshViewerMessageLabel.hidden = true;

    [self.meshViewerMessageLabel applyCustomStyleWithBackgroundColor:blackLabelColorWithLightAlpha];
    
    _meshRenderer = new MeshRenderer;
    _graphicsRenderer = new GraphicsRenderer(@"measurementTape.png");
    _viewpointController = new ViewpointController(self.view.frame.size.width, self.view.frame.size.height);
    
    [self setupGL];
    [self setupGestureRecognizer];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (_displayLink)
    {
        [_displayLink invalidate];
        _displayLink = nil;
    }
    
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(draw)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.needsDisplay = true;
    
    _viewpointController->reset();
    [self hideMeshViewerMessage:self.meshViewerMessageLabel];
    [_translationJoystick setEnabled:YES];
    [self.topViewSwitch setOn:NO];
    [self.holeFillingSwitch setEnabled:YES];
    [self.holeFillingSwitch setOn:false];
    [self.XRaySwitch setOn:false];
    
    [self enterMeasurementState:Measurement_Clear];
    
    _meshRenderer->setRenderingMode(MeshRenderer::RenderingModeTextured);
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)setupGestureRecognizer
{
    UIPinchGestureRecognizer *pinchScaleGesture = [[UIPinchGestureRecognizer alloc]
                                                   initWithTarget:self
                                                   action:@selector(pinchScaleGesture:)];
    [pinchScaleGesture setDelegate:self];
    [self.view addGestureRecognizer:pinchScaleGesture];
    
    
    UIRotationGestureRecognizer *rotationGesture = [[UIRotationGestureRecognizer alloc]
                                                    initWithTarget:self
                                                    action:@selector(rotationGesture:)];
    [rotationGesture setDelegate:self];
    [self.view addGestureRecognizer:rotationGesture];
    
    UITapGestureRecognizer *singleTapGesture = [[UITapGestureRecognizer alloc]
                                                      initWithTarget:self
                                                      action:@selector(singleTapGesture:)];
    singleTapGesture.numberOfTapsRequired = 1;
    
    
    [self.view addGestureRecognizer:singleTapGesture];
}

- (void)setupGL
{
    _meshRenderer->initializeGL();
    _graphicsRenderer->initializeGL();
    
    NSAssert (glGetError() == 0, @"Unexpected GL error, could not initialize the MeshRenderer");
    
    int framebufferWidth, framebufferHeight;
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &framebufferWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &framebufferHeight);
    
    float imageAspectRatio = 1.0f;
    
    // The iPad's diplay conveniently has a 4:3 aspect ratio just like our video feed.
    // Some iOS devices need to render to only a portion of the screen so that we don't distort
    // our RGB image. Alternatively, you could enlarge the viewport (losing visual information),
    // but fill the whole screen.
    if (((float)framebufferWidth/framebufferHeight) != 640.0f/480.0f)
        imageAspectRatio = 480.f/640.0f;
    
    _glViewport[0] = (framebufferWidth - framebufferWidth*imageAspectRatio)/2;
    _glViewport[1] = 0;
    _glViewport[2] = framebufferWidth*imageAspectRatio;
    _glViewport[3] = framebufferHeight;
}

- (void)dismissView
{
    if ([self.delegate respondsToSelector:@selector(meshViewWillDismiss)])
        [self.delegate meshViewWillDismiss];
    
    // Make sure we clear the data we don't need.
    _meshRenderer->releaseGLBuffers();
    _meshRenderer->releaseGLTextures();
    
    [_displayLink invalidate];
    _displayLink = nil;
    
    self.meshRef = nil;
    
    [(EAGLView *)self.view setContext:nil];
    
    [self dismissViewControllerAnimated:YES completion:^{
        if([self.delegate respondsToSelector:@selector(meshViewDidDismiss)])
            [self.delegate meshViewDidDismiss];
    }];
}

#pragma mark - MeshViewer Camera and Mesh Setup

- (void)setHorizontalFieldOfView:(float)fovXRadians aspectRatio:(float)aspectRatio
{
    _viewpointController->setCameraPerspective(fovXRadians, aspectRatio);

    // Save them for later in case we need a screenshot.
    _cameraFovBeforeUserInteractions = fovXRadians;
    _cameraAspectRatioBeforeUserInteractions = aspectRatio;
}

- (void)setCameraPose:(GLKMatrix4)pose
{
    _viewpointController->reset();
    _viewpointController->setCameraPose(pose);
    _cameraPoseBeforeUserInteractions = pose;
}

- (void)uploadMesh:(STMesh *)meshRef
{
    self.meshRef = meshRef;
    _meshRenderer->uploadMesh(meshRef);
    self.needsDisplay = true;
}

#pragma mark - Email

- (void)mailComposeController:(MFMailComposeViewController *)controller
          didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError *)error
{
    [self.mailViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)savePreviewImage:(NSString*)screenshotPath
{
    const int width = 320;
    const int height = 240;
    
    GLint currentFrameBuffer;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &currentFrameBuffer);
    
    // Create temp texture, framebuffer, renderbuffer
    glViewport(0, 0, width, height);
    
    // We are going to render the preview to a texture.
    GLuint outputTexture;
    glActiveTexture(GL_TEXTURE0);
    glGenTextures(1, &outputTexture);
    glBindTexture(GL_TEXTURE_2D, outputTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    
    // Create the offscreen framebuffers and attach the outputTexture to them.
    GLuint colorFrameBuffer, depthRenderBuffer;
    glGenFramebuffers(1, &colorFrameBuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, colorFrameBuffer);
    glGenRenderbuffers(1, &depthRenderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, depthRenderBuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, width, height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRenderBuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, outputTexture, 0);
    
    // Take the screenshot from the initial viewpoint, before user interactions.
    bool isInvertible = false;
    GLKMatrix4 modelViewMatrix = GLKMatrix4Invert(_cameraPoseBeforeUserInteractions, &isInvertible);
    NSAssert (isInvertible, @"Bad viewpoint.");
    GLKMatrix4 projectionMatrix = glProjectionMatrixFromPerspective(_cameraFovBeforeUserInteractions, _cameraAspectRatioBeforeUserInteractions);
    
    // Keep the current render mode
    MeshRenderer::RenderingMode previousRenderingMode = _meshRenderer->getRenderingMode();
    
    // Screenshot rendering mode, always use colors if possible.
    if ([self.meshRef hasPerVertexColors])
    {
        _meshRenderer->setRenderingMode( MeshRenderer::RenderingModePerVertexColor );
    }
    else if ([self.meshRef hasPerVertexUVTextureCoords] && [self.meshRef meshYCbCrTexture])
    {
        _meshRenderer->setRenderingMode( MeshRenderer::RenderingModeTextured );
    }
    else
    {
        _meshRenderer->setRenderingMode( MeshRenderer::RenderingModeLightedGray );
    }
    
    // Render the mesh at the given viewpoint.
    _meshRenderer->clear();
    _meshRenderer->render(projectionMatrix, modelViewMatrix);
    
    // back to current render mode
    _meshRenderer->setRenderingMode( previousRenderingMode );
    
    struct RgbaPixel { uint8_t rgba[4]; };
    std::vector<RgbaPixel> screenShotRgbaBuffer (width*height);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, screenShotRgbaBuffer.data());
    
    // We need to flip the vertice axis, because OpenGL reads out the buffer from the bottom.
    std::vector<RgbaPixel> rowBuffer (width);
    for (int h = 0; h < height/2; ++h)
    {
        RgbaPixel* screenShotDataTopRow    = screenShotRgbaBuffer.data() + h * width;
        RgbaPixel* screenShotDataBottomRow = screenShotRgbaBuffer.data() + (height - h - 1) * width;
        
        // Swap the top and bottom rows, using rowBuffer as a temporary placeholder.
        memcpy(rowBuffer.data(), screenShotDataTopRow, width * sizeof(RgbaPixel));
        memcpy(screenShotDataTopRow, screenShotDataBottomRow, width * sizeof (RgbaPixel));
        memcpy(screenShotDataBottomRow, rowBuffer.data(), width * sizeof (RgbaPixel));
    }
    
    saveJpegFromRGBABuffer([screenshotPath UTF8String], reinterpret_cast<uint8_t*>(screenShotRgbaBuffer.data()), width, height);

    glBindFramebuffer(GL_FRAMEBUFFER, currentFrameBuffer);
    glViewport(_glViewport[0], _glViewport[1], _glViewport[2], _glViewport[3]);
    
    // Release the rendering buffers.
    glDeleteTextures(1, &outputTexture);
    glDeleteFramebuffers(1, &colorFrameBuffer);
    glDeleteRenderbuffers(1, &depthRenderBuffer);
}

- (void)emailMesh
{
    self.mailViewController = [[MFMailComposeViewController alloc] init];
    
    if (!self.mailViewController)
    {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"The email could not be sent."
            message:@"Please make sure an email account is properly setup on this device."
            preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction * action) { }];
        
        [alert addAction:defaultAction];
        [self presentViewController:alert animated:YES completion:nil];
        
        return;
    }
    
    self.mailViewController.mailComposeDelegate = self;
    
    self.mailViewController.modalPresentationStyle = UIModalPresentationFormSheet;

    // Setup names and paths.
    NSString* attachmentDirectory = [NSSearchPathForDirectoriesInDomains( NSDocumentDirectory, NSUserDomainMask, YES ) objectAtIndex:0];

    NSString* zipFilename = @"Model.zip";
    NSString* zipTemporaryFilePath = [attachmentDirectory stringByAppendingPathComponent:zipFilename];
    
    NSString* screenShotFilename = @"Preview.jpg";
    NSString* screenShotTemporaryFilePath = [attachmentDirectory stringByAppendingPathComponent:screenShotFilename];
    
    // First save the screenshot to disk.
    [self savePreviewImage:screenShotTemporaryFilePath];
    
    NSMutableDictionary* attachmentInfo = [@{
                                             @"dir": attachmentDirectory,
                                             @"zipFilename": @"Model.zip",
                                             @"screenShotFilename": @"Preview.jpg"
                                             } mutableCopy];
    
    
    [self.mailViewController setSubject:@"3D Model"];

    NSString *messageBody =
        @"This model was captured with the open source Room Capture sample app in the Structure SDK.\n\n"
        "Check it out!\n\n"
        "More info about the Structure SDK: http://structure.io/developers";
    
    [self.mailViewController setMessageBody:messageBody isHTML:NO];

    // Generate the OBJ file in a background queue to avoid blocking.
    [self showMeshViewerMessage:self.meshViewerMessageLabel msg:@"Preparing Email..."];
    
    dispatch_async( dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(){
       
        [self.mailViewController addAttachmentData:[NSData dataWithContentsOfFile:screenShotTemporaryFilePath]
                                          mimeType:@"image/jpeg"
                                          fileName:screenShotFilename];
        
        // We want a ZIP with OBJ, MTL and JPG inside.
        NSDictionary* fileWriteOptions = @{kSTMeshWriteOptionFileFormatKey: @(STMeshWriteOptionFileFormatObjFileZip) };
        
        // Temporary path for the zip file.
        
        NSError* error;
        BOOL success = [self.meshRef writeToFile:zipTemporaryFilePath options:fileWriteOptions error:&error];
        if (!success)
        {
            NSLog (@"Could not save the mesh: %@", [error localizedDescription]);

            dispatch_async(dispatch_get_main_queue() , ^(){
                [self showMeshViewerMessage:self.meshViewerMessageLabel msg:@"Failed to save the OBJ file!"];
            
                // Hide the error message after 2 seconds.
                dispatch_after (dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue() , ^(){
                    [self hideMeshViewerMessage:self.meshViewerMessageLabel];
                });
            });
            
            return;
        }
        
        dispatch_async(dispatch_get_main_queue() , ^(){
            
            NSDictionary* attachmentsInfo = @{
                                              @"zipTemporaryFilePath": zipTemporaryFilePath,
                                              @"zipFilename": zipFilename,
                                              };
            [self didFinishSavingMeshWithAttachmentInfo:attachmentsInfo];
            
        });
    });
    
}

-(void) didFinishSavingMeshWithAttachmentInfo:(NSDictionary*)attachmentsInfo
{
    [self hideMeshViewerMessage:self.meshViewerMessageLabel];
    
    // We know the zip was saved there.
    NSString* zipFilePath = attachmentsInfo[@"zipTemporaryFilePath"];
    NSString* zipFilename = attachmentsInfo[@"zipFilename"];
    
    [self.mailViewController addAttachmentData:[NSData dataWithContentsOfFile:zipFilePath]
                                      mimeType:@"application/zip" fileName:zipFilename];
    
    [self presentViewController:self.mailViewController animated:YES completion:^(){}];
}

#pragma mark - Rendering

- (void)updateViewWith2DPosition:(UIView*)view onScreenPt:(GLKVector2)onScreenPt
{
    // scale point from [-1 1] to frame bound
    CGPoint center;
    center.x = onScreenPt.x;
    center.y = onScreenPt.y;
    view.hidden = false;
    view.center = center;
}

- (void)draw
{
    [(EAGLView *)self.view setFramebuffer];
    
    glViewport(_glViewport[0], _glViewport[1], _glViewport[2], _glViewport[3]);
    
    // Take this opportunity to process the Joystick information.
    _viewpointController->processJoystickRadiusAndTheta([_translationJoystick radius], [_translationJoystick theta]);
    
    static MeasurementState previousState;
    bool viewpointChanged = (_viewpointController->update()) || (_measurementState != previousState);
    previousState = _measurementState;
    
    // If nothing changed, do not waste time and resources rendering.
    if (!_needsDisplay && !viewpointChanged)
        return;
    
    GLKMatrix4 currentModelView = _viewpointController->currentGLModelViewMatrix();
    GLKMatrix4 currentProjection = _viewpointController->currentGLProjectionMatrix();
    
    _meshRenderer->clear();
    _meshRenderer->render(currentProjection, currentModelView);

    if (_measurementState == Measurement_Point2 || _measurementState == Measurement_Done)
    {
        GLKVector2 onScreenPt1;
        bool pt1OnScreen = [self point3dToScreenPoint:_pt1 screenPt:onScreenPt1];

        if (pt1OnScreen)
            [self updateViewWith2DPosition:_circle1 onScreenPt:onScreenPt1];
        else
            _circle1.hidden = true;
        
        if (_measurementState == Measurement_Done)
        {
            // from 3d point to screen point to [-1 1]
            GLKVector2 onScreenPt2;
            bool pt2OnScreen = [self point3dToScreenPoint:_pt2 screenPt:onScreenPt2];
            
            if (pt2OnScreen)
                [self updateViewWith2DPosition:_circle2 onScreenPt:onScreenPt2];
            else
                _circle2.hidden = true;
            
            GLKVector2 onScreenCenter;
            bool ptCenterOnScreen = [self point3dToScreenPoint:GLKVector3MultiplyScalar(GLKVector3Add(_pt1, _pt2), 0.5) screenPt:onScreenCenter];
            
            if (ptCenterOnScreen)
                [self updateViewWith2DPosition:_rulerText onScreenPt:onScreenCenter];
            else
                _rulerText.hidden = true;
        }
    }
    
    if (_measurementState == Measurement_Done)
        _graphicsRenderer->renderLine(_pt1, _pt2, currentProjection, currentModelView, _circle1.frame.origin.x < _circle2.frame.origin.x);
    
    [(EAGLView *)self.view presentFramebuffer];
    
    _needsDisplay = false;
}

#pragma mark - UI Control

- (void) hideMeshViewerMessage:(UILabel*)label
{
    [UIView animateWithDuration:0.5f animations:^{
        label.alpha = 0.0f;
    } completion:^(BOOL finished){
        [label setHidden:YES];
    }];
}

- (void)showMeshViewerMessage:(UILabel*)label msg:(NSString *)msg
{
    [label setText:msg];
    
    if (label.hidden == YES)
    {
        [label setHidden:NO];
        
        label.alpha = 0.0f;
        [UIView animateWithDuration:0.5f animations:^{
            label.alpha = 1.0f;
        }];
    }
}

- (IBAction)measurementButtonClicked:(id)sender
{
    
    if(_measurementState == Measurement_Clear)
        [self enterMeasurementState:Measurement_Point1];
    else if(_measurementState == Measurement_Done)
        [self enterMeasurementState:Measurement_Clear];
}

- (void)enterMeasurementState:(MeasurementState)state
{
    _measurementState = state;
    switch (_measurementState)
    {
        case Measurement_Clear:
        {
            
            self.measurementButton.enabled = true;
            [self.measurementButton setTitle:@"Measure" forState:UIControlStateNormal];

            [self hideMeshViewerMessage:self.measurementGuideLabel];
            _rulerText.hidden = true;
            _circle1.hidden = true;
            _circle2.hidden = true;

        }
            break;
        case Measurement_Point1:
        {
            self.measurementButton.enabled = false;
            _rulerText.hidden = true;
            _circle1.hidden = true;
            _circle2.hidden = true;
            [self showMeshViewerMessage:self.measurementGuideLabel msg:@"Tap to place first point."];
        }
            break;
        case Measurement_Point2:
        {
            _rulerText.hidden = true;
            _circle1.hidden = true;
            _circle2.hidden = true;
            [self showMeshViewerMessage:self.measurementGuideLabel msg:@"Tap to place second point."];
        }
            break;
        case Measurement_Done:
        {
            self.measurementButton.enabled = true;
            [self.measurementButton setTitle:@"Clear" forState:UIControlStateNormal];
            
            float distance = GLKVector3Length(GLKVector3Subtract(_pt2, _pt1));
            if (distance > 1.0f)
                _rulerText.text = [NSString stringWithFormat:@"%.2f m", distance];
            else
                _rulerText.text = [NSString stringWithFormat:@"%.1f cm", distance*100];
            _circle2.hidden = false;
            [self hideMeshViewerMessage:self.measurementGuideLabel];
        }
            break;
        default:
            break;
    }
    
    // Make sure we refresh the ruler.
    self.needsDisplay = true;
}

- (IBAction)topViewSwitchChanged:(id)sender
{
    bool topViewEnabled = [self.topViewSwitch isOn];
    _viewpointController->setTopViewModeEnabled (topViewEnabled);
    [_translationJoystick setEnabled:!topViewEnabled];
    self.needsDisplay = true;
}

- (IBAction)holeFillingSwitchChanged:(id)sender
{
    if (self.holeFillingSwitch.on)
    {
        if ([self.delegate respondsToSelector:@selector(meshViewDidRequestHoleFilling)])
        {
            [self.delegate meshViewDidRequestHoleFilling];
        }
    }
    else
    {
        if ([self.delegate respondsToSelector:@selector(meshViewDidRequestRegularMesh)])
        {
            [self.delegate meshViewDidRequestRegularMesh];
        }
    }
    self.needsDisplay = true;
}

- (IBAction)XRaySwitchChanged:(id)sender
{
    if ([self.XRaySwitch isOn])
        _meshRenderer->setRenderingMode(MeshRenderer::RenderingModeXRay);
    else
        _meshRenderer->setRenderingMode(MeshRenderer::RenderingModeTextured);
    self.needsDisplay = true;
}

#pragma mark - Touch and Gesture

- (void)pinchScaleGesture:(UIPinchGestureRecognizer *)gestureRecognizer
{
    if ([gestureRecognizer numberOfTouches] != 2)
        return;
    
    // Forward to the viewPointController
    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan)
        _viewpointController->onPinchGestureBegan([gestureRecognizer scale]);
    else if ( [gestureRecognizer state] == UIGestureRecognizerStateChanged)
        _viewpointController->onPinchGestureChanged([gestureRecognizer scale]);
}

- (void)rotationGesture:(UIRotationGestureRecognizer *)gestureRecognizer
{
    // Forward to the viewPointController
    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan)
        _viewpointController->onRotationGestureBegan([gestureRecognizer rotation]);
    else if ( [gestureRecognizer state] == UIGestureRecognizerStateChanged)
        _viewpointController->onRotationGestureChanged([gestureRecognizer rotation]);
}

-(GLKVector3)screenPointTo3dPoint :(GLKVector2)screenPt
{
    
    bool invertible;
    
    GLKMatrix4 invModelView = GLKMatrix4Invert(_viewpointController->currentGLModelViewMatrix(), &invertible);
    
    // scale to [-1 1]
    GLKVector2 screenPtScale = GLKVector2Make(2*screenPt.x/self.view.frame.size.width-1.0, 2*screenPt.y/self.view.frame.size.height-1.0);
    
    GLKMatrix4 currentProjection = _viewpointController->currentGLProjectionMatrix();
    
    // revert the projeciton effect
    float cotanX = currentProjection.m00;
    float cotanY = currentProjection.m11;
    GLKVector3 pt = GLKVector3Make(screenPtScale.x/cotanX, -screenPtScale.y/cotanY, 1.0);
    pt = GLKMatrix4MultiplyVector3WithTranslation(invModelView, pt);
    
    return pt;
}

- (bool)point3dToScreenPoint:(GLKVector3)pt screenPt:(GLKVector2&)screenPt
{
    
    GLKMatrix4 currentModelView = _viewpointController->currentGLModelViewMatrix();
    GLKVector3 ptTransformed = GLKMatrix4MultiplyVector3WithTranslation(currentModelView, pt);
    
    GLKMatrix4 currentProjection = _viewpointController->currentGLProjectionMatrix();
    
    float width = self.view.frame.size.width;
    float height = self.view.frame.size.height;
    
    float cotanX = currentProjection.m00;
    float cotanY = currentProjection.m11;
    
    screenPt = GLKVector2Make((ptTransformed.x/ptTransformed.z * cotanX + 1.0)*0.5 * width,
                          (-ptTransformed.y/ptTransformed.z * cotanY +1.0)*0.5*height);
    
    bool inView =  ptTransformed.z > 0 && [self.view pointInside:CGPointMake(screenPt.x, screenPt.y) withEvent:nil];
    return inView;
    
}

// measurement control
- (void)singleTapGesture:(UITapGestureRecognizer *)gestureRecognizer
{
    if (_measurementState != Measurement_Point1 && _measurementState != Measurement_Point2) {
        return;
    }
    
    if ([gestureRecognizer state] == UIGestureRecognizerStateEnded)
    {
        CGPoint touchPoint = [gestureRecognizer locationInView:self.view];
        
        GLKVector3 ptTouch = [self screenPointTo3dPoint:GLKVector2Make(touchPoint.x, touchPoint.y)];
        
        bool invertible;
        
        GLKMatrix4 invModelView = GLKMatrix4Invert(_viewpointController->currentGLModelViewMatrix(), &invertible);
        GLKVector3 ptCamera =GLKMatrix4MultiplyVector3WithTranslation(invModelView, GLKVector3Make(0, 0, 0));
        
        GLKVector3 direction = GLKVector3Subtract(ptTouch, ptCamera);
        float lenth = GLKVector3Length(direction);
        direction = GLKVector3DivideScalar(direction, lenth);
        
        GLKVector3 end = GLKVector3Add(ptCamera, GLKVector3MultiplyScalar(direction, 25));
        
        GLKVector3 intersection;
        bool hasIntersection = [_meshRef intersectWithRayOrigin:ptCamera rayEnd:end intersection:&intersection];
        if (hasIntersection)
        {
            if(_measurementState == Measurement_Point1)
            {
                _pt1 = intersection;
                [self enterMeasurementState:Measurement_Point2];
            }
            else
            {
                _pt2 = intersection;
                [self enterMeasurementState:Measurement_Done];
            }
        }
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}

// Only accept pinch gestures when the touch point does not lie within the joystick view.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    CGPoint touchPoint = [touch locationInView:_translationJoystick.view];
    if ([_translationJoystick.view pointInside:touchPoint withEvent:nil])
        return NO;
    else
        return YES;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    CGPoint touchPoint = [touch locationInView:self.view];
    NSTimeInterval timestamp = [touch timestamp];
    
    GLKVector2 touchPosVec;
    touchPosVec.x = touchPoint.x;
    touchPosVec.y = touchPoint.y;
    
    // Forward to the viewPointController
    _viewpointController->onTouchBegan(touchPosVec, timestamp);
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    CGPoint touchPoint = [touch locationInView:self.view];
    NSTimeInterval timestamp = [touch timestamp];
    
    GLKVector2 touchPosVec;
    touchPosVec.x = touchPoint.x;
    touchPosVec.y = touchPoint.y;
    // Forward to the viewPointController
    _viewpointController->onTouchChanged(touchPosVec, timestamp);
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    CGPoint touchPoint = [touch locationInView:self.view];
    NSTimeInterval timestamp = [touch timestamp];
    
    GLKVector2 touchPosVec;
    touchPosVec.x = touchPoint.x;
    touchPosVec.y = touchPoint.y;
    // Forward to the viewPointController
    _viewpointController->onTouchEnded(touchPosVec);
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
}

@end
