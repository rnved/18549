/*
 This file is part of the Structure SDK.
 Copyright © 2015 Occipital, Inc. All rights reserved.
 http://structure.io
 */

#import "MotionLogs.h"
#import "SCNTools.h"

#import <fstream>

/**
 ObjMatrix is a helper object for converting GLKMatrix4 from row-major to column major.
 */
@interface ObjMatrix : NSObject
{
    NSArray *m;
    float time;
}
- (id) initWithGLKMatrix4:(GLKMatrix4)matrix atTime:(float) t;
- (NSString *) toString;
- (GLKMatrix4) getMatrix;
- (float) getTime;
@end

@implementation ObjMatrix
- (id) initWithGLKMatrix4:(GLKMatrix4)matrix atTime:(float)t
{
    self = [super init];
    if(self)
    {
        NSMutableArray *ma = [[NSMutableArray alloc] init];
        for (int i = 0; i < 16 ; i++)
        {
            NSNumber *number = [NSNumber numberWithFloat:matrix.m[i]];
            [ma addObject:number];
        }
        m = [[NSArray alloc] initWithArray:ma];
        time = t;
    }
    return self;
}

- (NSString*) toString
{
    return [NSString stringWithFormat:@"%@ %@ %@ %@ \n %@ %@ %@ %@ \n %@ %@ %@ %@ \n %@ %@ %@ %@ \n ",
            m[0],  m[1],  m[2],  m[3],
            m[4],  m[5],  m[6],  m[7],
            m[8],  m[9],  m[10], m[11],
            m[12], m[13], m[14], m[15]];
}

- (GLKMatrix4) getMatrix
{
    // Convert to row-major from GLK column-major
    GLKMatrix4 g;
    g.m[0] =[[m objectAtIndex:0] floatValue];
    g.m[4] =[[m objectAtIndex:1] floatValue];
    g.m[8] =[[m objectAtIndex:2] floatValue];
    g.m[12] =[[m objectAtIndex:3] floatValue];
    g.m[1] =[[m objectAtIndex:4] floatValue];
    g.m[5] =[[m objectAtIndex:5] floatValue];
    g.m[9] =[[m objectAtIndex:6] floatValue];
    g.m[13] =[[m objectAtIndex:7] floatValue];
    g.m[2] =[[m objectAtIndex:8] floatValue];
    g.m[6] =[[m objectAtIndex:9] floatValue];
    g.m[10] =[[m objectAtIndex:10] floatValue];
    g.m[14] =[[m objectAtIndex:11] floatValue];
    g.m[3] =[[m objectAtIndex:12] floatValue];
    g.m[7] =[[m objectAtIndex:13] floatValue];
    g.m[11] =[[m objectAtIndex:14] floatValue];
    g.m[15] =[[m objectAtIndex:15] floatValue];
    g = GLKMatrix4RotateY( g, M_1_PI);
    g = GLKMatrix4ScaleWithVector3(g, GLKVector3Make(-1, -1, 1));
    return g;
}

- (float) getTime
{
    return time;
}
@end

//=====================================================

/**
 MotionLog represent an individual motion log
 */
@interface MotionLog : NSObject
{
    SCNNode *pointerNode;
    NSMutableArray *pathNodes;
    float *times;
    SCNMatrix4 *transforms;
    int motionDataIndex;
    int motionDataCount;
    NSTimeInterval _startTime;
}
- (id)initWithLogFilePath:(NSString*)filePath;
- (void)addIndicatorNode:(SCNNode*)indicatorNode toRootNode:(SCNNode*)rootNode;

- (void)beginAtTime:(NSTimeInterval)startTime;
- (void)updateAtTime:(NSTimeInterval)time;
- (void)reset;

@end

@implementation MotionLog

- (id)initWithLogFilePath:(NSString*)filePath
{
    self = [super init];
    
    NSStringEncoding encoding;
    NSError *error;
    NSString *fileContents = [NSString stringWithContentsOfFile:filePath usedEncoding:&encoding error:&error];
    
    NSArray *lines = [fileContents componentsSeparatedByString:@"\n"];
    
    if (error)
    {
        NSLog(@"Motion Log error: %@", error);
        return nil;
    }
    
    times = new float[lines.count];
    transforms = new SCNMatrix4[lines.count];
    
    motionDataCount = 0;
    for (id line in lines)
    {
        NSArray *lineComponents = [line componentsSeparatedByString:@" "];
        
        if (lineComponents.count < 16)
            continue;
        
        float time = [lineComponents[0] intValue]/1000.0;
        SCNMatrix4 transform;
        transform.m11 = [lineComponents[1] floatValue];
        transform.m12 = [lineComponents[2] floatValue];
        transform.m13 = [lineComponents[3] floatValue];
        transform.m14 = [lineComponents[4] floatValue];
        
        transform.m21 = [lineComponents[5] floatValue];
        transform.m22 = [lineComponents[6] floatValue];
        transform.m23 = [lineComponents[7] floatValue];
        transform.m24 = [lineComponents[8] floatValue];
        
        transform.m31 = [lineComponents[9] floatValue];
        transform.m32 = [lineComponents[10] floatValue];
        transform.m33 = [lineComponents[11] floatValue];
        transform.m34 = [lineComponents[12] floatValue];
        
        transform.m41 = [lineComponents[13] floatValue];
        transform.m42 = [lineComponents[14] floatValue];
        transform.m43 = [lineComponents[15] floatValue];
        transform.m44 = [lineComponents[16] floatValue];
        
        times[motionDataCount] = time;
        transforms[motionDataCount] = transform;
        motionDataCount++;
    }
    
    return self;
}

-(void)dealloc
{
    [pointerNode removeFromParentNode];
    for (id pathNode in pathNodes)
        [pathNode removeFromParentNode];
    [pathNodes removeAllObjects];
    delete[] times;
    delete[] transforms;
}

- (void)addIndicatorNode:(SCNNode*)indicatorNode toRootNode:(SCNNode*)rootNode
{
    if (motionDataCount == 0)
        return;
    
    pointerNode = indicatorNode;
    [rootNode addChildNode:pointerNode];
    [pointerNode setTransform:transforms[0]];
    
    pathNodes = [[NSMutableArray alloc] init];
    SCNNode *startEndMarker = [SCNNode nodeWithGeometry:[SCNBox boxWithWidth:0.2 height:0.2 length:0.2 chamferRadius:0]];
    [startEndMarker.geometry.firstMaterial.emission setContents:[UIColor whiteColor]];
    
    SCNNode *startMarker = [startEndMarker copy];
    [rootNode addChildNode:startMarker];
    [startMarker setTransform:transforms[0]];
    [pathNodes addObject:startMarker];
    
    SCNNode *endMarker = [startEndMarker copy];
    [rootNode addChildNode:endMarker];
    [endMarker setTransform:transforms[motionDataCount - 1]];
    [pathNodes addObject:endMarker];
    
    const int MARKER_FREQ = 2;
    for (int i = MARKER_FREQ; i < motionDataCount - 1; i += MARKER_FREQ)
    {
        SCNVector3 delta = [SCNTools subtractVector:[SCNTools getPositionFromTransform:transforms[i - 1]]
                                         fromVector:[SCNTools getPositionFromTransform:transforms[i + 1]]];
        float speed = [SCNTools vectorMagnitude:delta];
        float markerRadius = 0.05 - fminf(speed*0.05, 0.01);
        
        SCNNode *pathMarker = [SCNNode nodeWithGeometry:[SCNSphere sphereWithRadius:markerRadius]];
        [pathMarker.geometry.firstMaterial.emission setContents:[UIColor whiteColor]];
        [rootNode addChildNode:pathMarker];
        [pathMarker setTransform:transforms[i]];
        [pathNodes addObject:pathMarker];
    }
}

- (void)beginAtTime:(NSTimeInterval)startTime
{
    motionDataIndex = 0;
    _startTime = startTime;
    
    if (motionDataCount > 0)
        [pointerNode setTransform:transforms[0]];
}

- (void)updateAtTime:(NSTimeInterval)time
{
    if (motionDataCount == 0 ||
        motionDataIndex >= motionDataCount - 1)
        return;
    
    motionDataIndex++;
    
    if (motionDataIndex >= motionDataCount - 1)
    {
        pointerNode.geometry.firstMaterial.emission.contents = [UIColor whiteColor];
    }
    else
    {
        [pointerNode setTransform:transforms[motionDataIndex]];
    }
}

- (void)reset
{
    if (motionDataCount == 0)
        return;
    
    motionDataIndex = 0;
    [pointerNode setTransform:transforms[motionDataIndex]];
}

@end

//=====================================================

@implementation MotionLogs

std::ofstream gameCameraPosesLogFile;
std::ofstream trackerEstimatesLogFile;

BOOL playbackHasBegun = NO;

NSMutableArray *motionLogs;
NSArray *motionLogFiles;

BOOL recordingMotionLog = NO;
BOOL recordingStartTimeStarted;
NSMutableArray *transforms;
double recordingStartTime;
double lastTime;

SCNNode *pointerParentNode;
SCNNode *rootNode;
UIButton *playMotionLogsButton;

+ (NSString*)motionLogsDirectory
{
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
}

// Opens any recorded path data from the apps documents directory
+ (void)refreshLogs
{
    motionLogs = [[NSMutableArray alloc] init];
    
    // Check iTunes File System for logs of the form <timestamp>.gameCameraPoses.log
    NSArray *dirFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self motionLogsDirectory] error:nil];
    motionLogFiles = [dirFiles filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self ENDSWITH '.GameCameraPoses.log'"]];
    
    if (motionLogFiles.count == 0)
        return;
    
    // WARNING: if you want to load a bunch of motion logs, we recommend a dispatch_async
    MotionLog *motionLog = [[MotionLog alloc] initWithLogFilePath:[NSString stringWithFormat:@"%@/%@",
                                                                   [self motionLogsDirectory], motionLogFiles.lastObject]];
    [motionLogs addObject:motionLog];
    [motionLog addIndicatorNode:[pointerParentNode clone] toRootNode:rootNode];
    
    [playMotionLogsButton setHidden:([MotionLogs getLogCount] == 0)];
    [playMotionLogsButton setTitle:[NSString stringWithFormat:@"Play Last Path (of %i)", [MotionLogs getLogCount]] forState:UIControlStateNormal];

    playbackHasBegun = NO;
}

// Specific for SceneKit this takes the incoming data for the plotted paths and then
// places a little model on the recorded path for visualizing playback.
+ (void) loadLogsWithRootNode:(SCNNode*)givenRootNode andPlayButton:(UIButton*)givenPlayMotionLogsButton
{
    SCNScene *pointerScene = [SCNScene sceneNamed:@"models.scnassets/AxisPointer.dae"];
    SCNNode *pointerSubNode = pointerScene.rootNode.childNodes[0];
    [pointerSubNode setScale:SCNVector3Make(0.3, 0.3, 0.3)];
    
    const float FRUSTRUM_SCALE = 0.7;
    SCNNode *frustrumNode = [SCNNode nodeWithGeometry:[SCNPyramid pyramidWithWidth:FRUSTRUM_SCALE*4/3.0f height:FRUSTRUM_SCALE length:FRUSTRUM_SCALE]];
    [frustrumNode setPosition:SCNVector3Make(0, 0, -FRUSTRUM_SCALE)];
    [frustrumNode.geometry.firstMaterial.emission setContents:[UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:1.0]];
    [frustrumNode setEulerAngles:SCNVector3Make(M_PI*0.5f, 0, 0)];
    [frustrumNode setOpacity:0.8];
    
    pointerParentNode = [SCNNode node];
    [pointerParentNode addChildNode:pointerSubNode];
    [pointerParentNode addChildNode:frustrumNode];
    rootNode = givenRootNode;
    playMotionLogsButton = givenPlayMotionLogsButton;
    
    [self refreshLogs];
}

+ (int)getLogCount
{
    return (int)motionLogFiles.count;
}

+ (BOOL)isPlaying
{
    return playbackHasBegun;
}

+ (void)beginAtTime:(NSTimeInterval)startTime
{
    // Starts the playback of motion logs
    playbackHasBegun = YES;
    for (id motionLog in motionLogs)
        [motionLog beginAtTime:startTime];
    
}

+ (void)resetPlayback
{
    playbackHasBegun = NO;
    for (id motionLog in motionLogs)
        [motionLog reset];
}

+ (void)updateAtTime:(NSTimeInterval)time
{
    if (!playbackHasBegun)
        return;
    
    for (id motionLog in motionLogs)
        [motionLog updateAtTime:time];
}

#pragma mark - Logging input

// Recording the matrix of the camera POV each time stamp here
+ (void)logGameCameraPose:(SCNMatrix4)povTransform atTime:(double)timestamp
{
    if(!recordingMotionLog)
    {
        return;
    }
    
    int msTimestamp = int(1e3*timestamp);
    
    if (!gameCameraPosesLogFile.is_open())
    {
        NSString* date = [self MakeLongTimeStamp:@"YYYYMMdd_HHmmss"];
        NSString* logPath = [NSString stringWithFormat:@"%@/%@.GameCameraPoses.log",
                             [self motionLogsDirectory],
                             date];

        gameCameraPosesLogFile.open ([logPath UTF8String]);
    }
    
    gameCameraPosesLogFile << msTimestamp << " ";
    gameCameraPosesLogFile
    << povTransform.m11 << " " << povTransform.m12 << " " << povTransform.m13 << " " << povTransform.m14 << " "
    << povTransform.m21 << " " << povTransform.m22 << " " << povTransform.m23 << " " << povTransform.m24 << " "
    << povTransform.m31 << " " << povTransform.m32 << " " << povTransform.m33 << " " << povTransform.m34 << " "
    << povTransform.m41 << " " << povTransform.m42 << " " << povTransform.m43 << " " << povTransform.m44 << std::endl;
}

+ (void)logTrackerPose:(GLKMatrix4)povTransform atTime:(double)timestamp
{
    if(!recordingMotionLog)
    {
        return;
    }
    
    if(!recordingStartTimeStarted)
    {
        recordingStartTime = timestamp;
        recordingStartTimeStarted = YES;
        lastTime = 0;
    }
    
    double frameTime = (double)(timestamp - recordingStartTime);
    if(frameTime > 0.0 && frameTime > lastTime)
    {
        //skip duplicate frame times
        lastTime = frameTime;
        [transforms addObject:[[ObjMatrix alloc] initWithGLKMatrix4:povTransform atTime:frameTime]];
    }
}

+ (void) startMotionLogRecording
{
    //allow tracker to start updating.
    recordingMotionLog = YES;
    recordingStartTimeStarted = NO;
    transforms = [[NSMutableArray alloc] init];
}

/// When the recording stops we write the dae collada file to the iOS file directory
+ (void) stopMotionLogRecording
{
    if(!recordingMotionLog)
        return;
    
    if (!trackerEstimatesLogFile.is_open())
    {
        NSString* date = [self MakeLongTimeStamp:@"YYYYMMdd_HHmmss"];
        NSString* logPath = [NSString stringWithFormat:@"%@/%@.WorldCameraPoses.dae",
                             [self motionLogsDirectory],
                             date];
        
        trackerEstimatesLogFile.open([logPath UTF8String]);
        
        if(trackerEstimatesLogFile.is_open())
        {
            trackerEstimatesLogFile << [[MotionLogs writeColladaHeaderForFile:logPath dateString:date] UTF8String];
            
            trackerEstimatesLogFile << [[MotionLogs writeAnimationTimeLine:transforms] UTF8String];
            
            trackerEstimatesLogFile << [[MotionLogs writeTransformOutput:transforms] UTF8String];
            
            trackerEstimatesLogFile << [[MotionLogs writeInterpolations:(int)[transforms count]]UTF8String];
            
            ObjMatrix *oMat = [transforms objectAtIndex:0];
            GLKMatrix4 gMat = [oMat getMatrix];
            
            trackerEstimatesLogFile << [[MotionLogs closeAnimationMatrix:gMat] UTF8String];
            
            trackerEstimatesLogFile.close();
        }
    }
    
    gameCameraPosesLogFile.close();
    recordingMotionLog = NO;
    
    [self refreshLogs];
}

+ (BOOL) isRecording
{
    return recordingMotionLog;
}

#pragma mark - Collada (DAE) formatting

// Create a simple collada asset header section
+ (NSMutableString*) writeColladaHeaderForFile:(NSString*)fileName dateString:(NSString*) date
{
    NSMutableString *xmlString = [[NSMutableString alloc] init];
    [xmlString appendString:@"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"];
    [xmlString appendString:@"<COLLADA xmlns=\"http://www.collada.org/2005/11/COLLADASchema\" version=\"1.4.1\">\n"];
    [xmlString appendString:@"    <asset>\n"];
    [xmlString appendString:@"        <contributor>\n"];
    [xmlString appendString:@"            <authoring_tool>StructurePlugin</authoring_tool>\n"];
    [xmlString appendString:@"            <comments>\n"];
    [xmlString appendString:@"                Bake Matrices: Yes;\n"];
    [xmlString appendString:@"                Formatted Arrays: Yes;\n"];
    [xmlString appendString:@"            </comments>\n"];
    [xmlString appendString:[NSString stringWithFormat:@"                <source_data>%@</source_data>\n", fileName]];
    [xmlString appendString:@"        </contributor>\n"];
    [xmlString appendString:[NSString stringWithFormat:@"        <created>%@</created>\n", date]];
    [xmlString appendString:[NSString stringWithFormat:@"        <modified>%@</modified>\n", date]];
    [xmlString appendString:@"        <unit name=\"centimeter\" meter=\"0.01\" />\n"];
    [xmlString appendString:@"        <up_axis>Y_UP</up_axis>\n"];
    [xmlString appendString:@"    </asset>\n"];
    return xmlString;
}

// Create and assign timeline where keyframes appear
+ (NSMutableString*) writeAnimationTimeLine:(NSArray*) transforms
{
    unsigned long count = [transforms count];
    NSMutableString *xmlString = [[NSMutableString alloc] init];
    [xmlString appendString:@"\n"];
    [xmlString appendString:@"    <library_animations>\n"];
    [xmlString appendString:@"        <animation id=\"LocatorNode_transform\">\n"];
    [xmlString appendString:@"            <source id=\"LocatorNode_transform-input\">\n"];
    [xmlString appendString:[NSString stringWithFormat:@"                <float_array id=\"LocatorNode_transform-input-array\" count=\"%lu\">", count]];
    
    // Write down the times we have in our transforms array
    for(int i = 0; i < count; i++)
    {
        if(i % 16 == 0)
        {
            [xmlString appendString:@"\n"];
            [xmlString appendString:[self tabs:5]];
        }
        NSNumberFormatter *formatter = [NSNumberFormatter new];
        [formatter setRoundingMode:NSNumberFormatterRoundFloor];
        [formatter setMinimumIntegerDigits:1];
        [formatter setMinimumFractionDigits:6];
        [formatter setMaximumFractionDigits:6];
        NSString *numberString = [formatter stringFromNumber:@([[transforms objectAtIndex:i] getTime])];
        [xmlString appendString:numberString];
        [xmlString appendString:@" "];
    }
    [xmlString appendString:@"\n"];
    [xmlString appendString:@"                </float_array>\n"];
    [xmlString appendString:@"                <technique_common>\n"];
    [xmlString appendString:[NSString stringWithFormat:@"                    <accessor source=\"#LocatorNode_transform-input-array\" stride=\"1\" count=\"%lu\">\n", count]];
    [xmlString appendString:@"                        <param name=\"TIME\" type=\"float\" />\n"];
    [xmlString appendString:@"                    </accessor>\n"];
    [xmlString appendString:@"                </technique_common>\n"];
    [xmlString appendString:@"            </source>\n\n"];
    return xmlString;
}

// Matrix array
+ (NSMutableString*) writeTransformOutput:(NSArray*)transforms
{
    unsigned long count = [transforms count];
    NSMutableString *xmlString = [[NSMutableString alloc] init];
    [xmlString appendString:@"            <source id=\"LocatorNode_transform-output\">\n"];
    [xmlString appendString:[NSString stringWithFormat:@"                <float_array id=\"LocatorNode_transform-output-array\" count=\"%lu\">\n", (count * 16) ]];
    
    for(ObjMatrix *xform in transforms)
    {
        GLKMatrix4 g = [xform getMatrix];
        [xmlString appendString:[self tabs:5]];
        for( int i = 0; i < 16 ; i++)
        {
            NSNumberFormatter *formatter = [NSNumberFormatter new];
            [formatter setRoundingMode:NSNumberFormatterRoundFloor];
            [formatter setMinimumIntegerDigits:1];
            [formatter setMinimumFractionDigits:6];
            [formatter setMaximumFractionDigits:6];
            NSString *numberString = [formatter stringFromNumber:@(g.m[i])];
            [xmlString appendString:numberString];
            [xmlString appendString:@" "];
        }
        [xmlString appendString:@"\n"];
    }
    
    [xmlString appendString:@"                </float_array>\n"];
    [xmlString appendString:@"                <technique_common>\n"];
    [xmlString appendString:[NSString stringWithFormat:@"                    <accessor source=\"#LocatorNode_transform-output-array\" stride=\"16\" count=\"%lu\">\n", count]];
    [xmlString appendString:@"                        <param name=\"transform\" type=\"float4x4\" />\n"];
    [xmlString appendString:@"                    </accessor>\n"];
    [xmlString appendString:@"                </technique_common>\n"];
    [xmlString appendString:@"            </source>\n\n"];
    return xmlString;
}

+ (NSMutableString*) writeInterpolations:(int) count
{
    NSMutableString *xmlString = [[NSMutableString alloc] init];
    [xmlString appendString:@"            <source id=\"LocatorNode_transform-interpolations\">\n"];
    [xmlString appendString:[NSString stringWithFormat:@"                <Name_array id=\"LocatorNode_transform-interpolations-array\" count=\"%i\">", count]];
    for(int i = 0; i < count; ++i)
    {
        if(i %16 == 0)
        {
            [xmlString appendString:@"\n"];
            [xmlString appendString:[self tabs:5]];
        }
        [xmlString appendString:@"STEP"];
        [xmlString appendString:@" "];
    }
    [xmlString appendString:@"\n"];
    [xmlString appendString:@"                </Name_array>\n"];
    [xmlString appendString:@"                <technique_common>\n"];
    [xmlString appendString:[NSString stringWithFormat:@"                    <accessor source=\"#LocatorNode_transform-interpolations-array\" stride=\"1\" count=\"%d\">\n", count]];
    [xmlString appendString:@"                        <param name=\"INTERPOLATION\" type=\"Name\" />\n"];
    [xmlString appendString:@"                    </accessor>\n"];
    [xmlString appendString:@"                </technique_common>\n"];
    [xmlString appendString:@"            </source>\n\n"];
    
    // Close animations
    [xmlString appendString:@"            <sampler id=\"LocatorNode_transform-sampler\">\n"];
    [xmlString appendString:@"                <input semantic=\"INPUT\" source=\"#LocatorNode_transform-input\" />\n"];
    [xmlString appendString:@"                <input semantic=\"OUTPUT\" source=\"#LocatorNode_transform-output\" />\n"];
    [xmlString appendString:@"                <input semantic=\"INTERPOLATION\" source=\"#LocatorNode_transform-interpolations\" />\n"];
    [xmlString appendString:@"            </sampler>\n"];
    [xmlString appendString:@"            <channel source=\"#LocatorNode_transform-sampler\" target=\"LocatorNode/transform\" />\n"];
    [xmlString appendString:@"        </animation>\n"];
    [xmlString appendString:@"    </library_animations>\n\n"];
    return xmlString;
}

+ (NSMutableString*) closeAnimationMatrix:(GLKMatrix4) startPose
{
    NSMutableString *xmlString = [[NSMutableString alloc] init];
    [xmlString appendString:@"    <library_cameras>\n"];
    [xmlString appendString:@"        <camera id=\"Camera-Camera1\" name=\"Camera\">\n"];
    [xmlString appendString:@"            <optics>\n"];
    [xmlString appendString:@"                <technique_common>\n"];
    [xmlString appendString:@"                    <perspective>\n"];
    [xmlString appendString:@"                        <xfov sid=\"HFOV\">39.5978</xfov>\n"];
    [xmlString appendString:@"                        <yfov sid=\"YFOV\">26.9915</yfov>\n"];
    [xmlString appendString:@"                        <znear sid=\"near_clip\">0.01</znear>\n"];
    [xmlString appendString:@"                        <zfar sid=\"far_clip\">10000</zfar>\n"];
    [xmlString appendString:@"                    </perspective>\n"];
    [xmlString appendString:@"                </technique_common>\n"];
    [xmlString appendString:@"            </optics>\n"];
    [xmlString appendString:@"        </camera>\n"];
    [xmlString appendString:@"    </library_cameras>\n\n"];
    [xmlString appendString:@"    <library_visual_scenes>\n"];
    [xmlString appendString:@"        <visual_scene id=\"DefaultScene\">\n"];
    [xmlString appendString:@"             <node id=\"LocatorNode\" name=\"Locator\" type=\"NODE\" sid=\"Locator1\">\n"];
    [xmlString appendString:@"                 <matrix sid=\"transform\"> \n"];
    [xmlString appendString:[NSString stringWithFormat:@"                    %f %f %f %f\n", startPose.m[0], startPose.m[1], startPose.m[2], startPose.m[3]]];
    [xmlString appendString:[NSString stringWithFormat:@"                    %f %f %f %f\n", startPose.m[4], startPose.m[5], startPose.m[6], startPose.m[7]]];
    [xmlString appendString:[NSString stringWithFormat:@"                    %f %f %f %f\n", startPose.m[8], startPose.m[9], startPose.m[10], startPose.m[11]]];
    [xmlString appendString:[NSString stringWithFormat:@"                    %f %f %f %f\n", startPose.m[12], startPose.m[13], startPose.m[14], startPose.m[15]]];
    [xmlString appendString:@"                 </matrix>\n\n"];
    [xmlString appendString:@"                 <node id=\"Camera-Camera1Node\" name=\"Camera\" type=\"NODE\" sid=\"Camera\">\n"];
    [xmlString appendString:@"                 <matrix sid=\"transform\">\n"]; //rotate the camera under the xform node 180 on z
    [xmlString appendString:@"                     1.000000 0.000000 0.000000 0.000000 \n"];
    [xmlString appendString:@"                     0.000000 -1.000000 0.000000 0.000000 \n"];
    [xmlString appendString:@"                     0.000000 0.000000 -1.000000 0.000000 \n"];
    [xmlString appendString:@"                     0.000000 0.000000 0.000000 1.000000 \n"];
    [xmlString appendString:@"                 </matrix> \n"];
    [xmlString appendString:@"                 <instance_camera url=\"#Camera-Camera1\" />\n"];
    [xmlString appendString:@"                 </node>\n"];
    [xmlString appendString:@"            </node>\n"];
    [xmlString appendString:@"        </visual_scene>\n"];
    [xmlString appendString:@"    </library_visual_scenes>\n\n"];
    [xmlString appendString:@"    <scene>\n"];
    [xmlString appendString:@"        <instance_visual_scene url=\"#DefaultScene\" />\n"];
    [xmlString appendString:@"    </scene>\n"];
    [xmlString appendString:@"</COLLADA>\n"];
    return xmlString;
}

+(NSMutableString*) tabs:(int)t
{
    NSMutableString *xmlString = [[NSMutableString alloc] init];
    for (int i = 0; i < t; i++)
    {
        [xmlString appendString:@"    "];
    }
    return xmlString;
}

+ (NSString*) MakeLongTimeStamp:(NSString * ) format
{
    NSDate *date = [NSDate date];
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    
    [dateFormat setDateFormat:format];
    NSString *dateString = [dateFormat stringFromDate:date];
    return dateString;
}

@end
