/*
 This file is part of the Structure SDK.
 Copyright © 2015 Occipital, Inc. All rights reserved.
 http://structure.io
 */

#import "SCNTools.h"
#import <GLKit/GLKit.h>

#pragma mark - Math and Transforms

NSString* NSStringFromSCNVector3(SCNVector3 vector)
{
    return [NSString stringWithFormat:@" [ %f %f %f ]", vector.x, vector.y, vector.z];
}

@implementation SCNTools

+ (SCNVector3)addVector:(SCNVector3)a toVector:(SCNVector3) b
{
    return SCNVector3Make(a.x + b.x,
                          a.y + b.y,
                          a.z + b.z);
}

+ (SCNVector3)subtractVector:(SCNVector3)b fromVector:(SCNVector3) a
{
    return SCNVector3Make(a.x - b.x,
                          a.y - b.y,
                          a.z - b.z);
}

+ (float)vectorMagnitude:( SCNVector3 ) vectorA
{
    float Ax = vectorA.x * vectorA.x;
    float Ay = vectorA.y * vectorA.y;
    float Az = vectorA.z * vectorA.z;
    return ABS(sqrtf(Ax + Ay + Az));
}

+ (SCNVector3)normalizedVector:( SCNVector3 ) vectorA
{
    float magnitude = [self vectorMagnitude:vectorA];
    float Ax = vectorA.x/magnitude;
    float Ay = vectorA.y/magnitude;
    float Az = vectorA.z/magnitude;
    return SCNVector3Make(Ax, Ay, Az);
}

+ (float)distanceFromVector:( SCNVector3 ) vectorA toVector: ( SCNVector3 ) vectorB
{
    return [self vectorMagnitude:[self subtractVector:vectorB fromVector:vectorA]];
}

+ (SCNVector3)directionFromVector:( SCNVector3 ) vectorA toVector: ( SCNVector3 ) vectorB
{
    float Ax = vectorB.x - vectorA.x;
    float Ay = vectorB.y - vectorA.y;
    float Az = vectorB.z - vectorA.z;
    return SCNVector3Make(Ax, Ay, Az);
}

+ (SCNVector3)multiplyVector:( SCNVector3 ) v byFloat: ( float ) factor
{
    return SCNVector3Make(factor*v.x, factor*v.y, factor*v.z);
}

+ (SCNVector3)divideVector:( SCNVector3 ) vectorA byDouble: ( double ) value
{
    float Ax = vectorA.x / value;
    float Ay = vectorA.y / value;
    float Az = vectorA.z / value;
    return SCNVector3Make(Ax, Ay, Az);
}

+ (float)dotProduct:(SCNVector3)vectorA andVector:(SCNVector3)vectorB
{
    return vectorA.x * vectorB.x + vectorA.y * vectorB.y + vectorA.z * vectorB.z;
}

+ (float)angleBetweenVector:(SCNVector3)vectorA andVector:(SCNVector3)vectorB
{
    float dot = [self dotProduct:vectorA andVector:vectorB];
    return acos(dot/([self vectorMagnitude:vectorA]*[self vectorMagnitude:vectorB]));
}

+ (SCNVector3)capSCNVector3Length:(SCNVector3)vector atFloat:(float) maxLength
{
    float length = [self vectorMagnitude:vector];
    if (length > maxLength) {
        vector = [SCNTools multiplyVector:vector byFloat:maxLength/length];
    }
    return vector;
}

#define ARC4RANDOM_MAX      0x100000000
+ (float)randf
{
    //returns a random float (-1, 1)
    return 2*(float) arc4random() / ARC4RANDOM_MAX - 1;
}

#pragma mark - command line logging functions

+ (void)logSCNVector3:(SCNVector3)vector
{
    NSLog(@"\n %@ \n", NSStringFromSCNVector3(vector));
}

+ (void)logSCNVector4:(SCNVector4)vector
{
    NSLog(@"\n [ %f %f %f %f ] \n", vector.w, vector.x, vector.y, vector.z);
}

+ (void)logSCNMatrix4:(SCNMatrix4)matrix
{
    
    NSLog(@"\n%f %f %f %f\n%f %f %f %f\n%f %f %f %f\n%f %f %f %f",
          matrix.m11, matrix.m21, matrix.m31, matrix.m41,
          matrix.m12, matrix.m22, matrix.m32, matrix.m42,
          matrix.m13, matrix.m23, matrix.m33, matrix.m43,
          matrix.m14, matrix.m24, matrix.m34, matrix.m44);
}

+ (void)logGLKMatrix4:(GLKMatrix4)matrix
{
    NSLog(@"\n%f %f %f %f\n%f %f %f %f\n%f %f %f %f\n%f %f %f %f",
          matrix.m00, matrix.m10, matrix.m20, matrix.m30,
          matrix.m01, matrix.m11, matrix.m21, matrix.m31,
          matrix.m02, matrix.m12, matrix.m22, matrix.m32,
          matrix.m03, matrix.m13, matrix.m23, matrix.m33);
}

+ (SCNVector3)getPositionFromTransform:(SCNMatrix4)m
{
    SCNVector3 pos = SCNVector3Make(m.m41, m.m42, m.m43);
    return pos;
}

+ (SCNVector3)getWorldPos:(SCNNode *)n
{
    return [self getPositionFromTransform:n.presentationNode.worldTransform];
}

+ (SCNVector3)vectorFromNode:(SCNNode *)fromNode toNode:(SCNNode*)toNode
{
    SCNVector3 diff = [SCNTools subtractVector:[SCNTools getWorldPos:toNode] fromVector:[SCNTools getWorldPos:fromNode]];
    
    return diff;
}

+ (float)distancefromNode:(SCNNode *)fromNode toNode:(SCNNode*)toNode
{
    SCNVector3 diff = [self vectorFromNode:fromNode toNode:toNode];
    return [self vectorMagnitude:diff];
}

+ (SCNVector3)getLookAtVectorOfNodeLocal:(SCNNode*)n
{
    SCNMatrix4 lookVectorMatrix = SCNMatrix4MakeTranslation(0, 0, -1);
    SCNMatrix4 nodeRotationMatrix = [self isolateRotationFromSCNMatrix4:n.presentationNode.transform];
    SCNMatrix4 lookVectorMatrixTransformed = SCNMatrix4Mult(lookVectorMatrix, nodeRotationMatrix);
    
    return [self normalizedVector:[self getPositionFromTransform:lookVectorMatrixTransformed]];
}

+ (SCNVector3)getLookAtVectorOfNode:(SCNNode*)n
{
    SCNMatrix4 lookVectorMatrix = SCNMatrix4MakeTranslation(0, 0, -1);
    SCNMatrix4 nodeRotationMatrix = [self isolateRotationFromSCNMatrix4:n.presentationNode.worldTransform];
    SCNMatrix4 lookVectorMatrixTransformed = SCNMatrix4Mult(lookVectorMatrix, nodeRotationMatrix);
    
    return [self normalizedVector:[self getPositionFromTransform:lookVectorMatrixTransformed]];
}

SCNMatrix4 SCNMatrix4MakeFromSCNVector3(SCNVector3 vector)
{
    return SCNMatrix4MakeTranslation(vector.x, vector.y, vector.z);
}

+ (SCNVector3)multiplyVector:(SCNVector3)vector bySCNMatrix4:(SCNMatrix4)matrix
{
    SCNMatrix4 vectorMatrix = SCNMatrix4MakeFromSCNVector3(vector);
    SCNMatrix4 vectorTransformed = SCNMatrix4Mult(vectorMatrix, matrix);
    return [self getPositionFromTransform:vectorTransformed];
}

+ (SCNVector3)crossProductOfSCNVector3:(SCNVector3)vectorA with:(SCNVector3)vectorB
{
    GLKVector3 product = GLKVector3CrossProduct(SCNVector3ToGLKVector3(vectorA), SCNVector3ToGLKVector3(vectorB));
    return SCNVector3FromGLKVector3(product);
}

+ (SCNMatrix4)isolateAxisRotationFromSCNMatrix4:(SCNMatrix4)rotationMatrix axis:(SCNVector3)axis orthoVector:(SCNVector3)orthoVector
{
    // A user-supplied orthoAxis shouldn't be necessary, but it is easier than just guessing one.
    
    // Normalize just in case
    axis = [self normalizedVector:axis];
    orthoVector = [self normalizedVector:orthoVector];
    
    SCNVector3 orthoVectorRotated = [self multiplyVector:orthoVector bySCNMatrix4:rotationMatrix];
    
    if ([self vectorMagnitude:orthoVectorRotated] < 0.01)
    {
        // Use new orthogonal vector
        NSLog(@"use new orthogonal vector (as first was rotated out)");
        orthoVector = [self crossProductOfSCNVector3:axis with:orthoVector];
        orthoVectorRotated = [self multiplyVector:orthoVector bySCNMatrix4:rotationMatrix];
    }
    
    GLKVector3 axisGLK = SCNVector3ToGLKVector3(axis);
    GLKVector3 orthoVectorGLK = SCNVector3ToGLKVector3(orthoVector);
    GLKVector3 orthoVectorRotatedGLK = SCNVector3ToGLKVector3(orthoVectorRotated);
    
    // Project orthoVectorRotated onto axis normal
    GLKVector3 orthoVectorProjectedGLK = GLKVector3Subtract(orthoVectorRotatedGLK, GLKVector3Project(orthoVectorRotatedGLK, axisGLK));
    
    float angleAboutAxis = [self angleBetweenVector:SCNVector3FromGLKVector3(orthoVectorProjectedGLK) andVector:orthoVector];
    
    if (isnan(angleAboutAxis))
        return SCNMatrix4Identity;
    
    // Now to calculate angle sign:
    GLKVector3 crossProductResultGLK = GLKVector3CrossProduct(orthoVectorProjectedGLK, orthoVectorGLK);
    
    if (GLKVector3Length(crossProductResultGLK) == 0)
    {
        NSLog(@"isolateAxisRotationFromSCNMatrix4: no rotation found");
        [self logSCNMatrix4:rotationMatrix];
        [self logSCNVector3:orthoVectorRotated];
        
        return SCNMatrix4Identity;
    }

    // crossProductResult should be coincident with axis - sanity check
    SCNVector3 crossProductResult = SCNVector3FromGLKVector3(crossProductResultGLK);
    
    float dotProductResult = [self dotProduct:crossProductResult andVector:axis];
    if (dotProductResult < 0)
        angleAboutAxis *= -1;
    
    return SCNMatrix4MakeRotation(angleAboutAxis, axis.x, axis.y, axis.z);
}

+ (SCNMatrix4)isolateRotationFromSCNMatrix4:(SCNMatrix4)matrix
{
    SCNMatrix4 isolateRot = matrix;
    isolateRot.m41 = 0;
    isolateRot.m42 = 0;
    isolateRot.m43 = 0;
    return isolateRot;
}

+ (SCNMatrix4)convertSTTrackerPoseToSceneKitPose:(GLKMatrix4)stTrackerPose
{
    // The SceneKit and STTracker coordinate spaces have opposite Y and Z axes
    GLKMatrix4 flipYZ = GLKMatrix4MakeScale(1, -1, -1);
    GLKMatrix4 m = GLKMatrix4Multiply(flipYZ, stTrackerPose);
    m = GLKMatrix4Multiply(m, flipYZ);
    SCNMatrix4 SCNSceneKitCameraPose = SCNMatrix4FromGLKMatrix4(m);
    return SCNSceneKitCameraPose;
}

#pragma mark - Object Creation
+ (SCNScene*)loadSceneFromPlist:(NSString *)list
{
    SCNScene *scene = [[SCNScene alloc] init];
    
    // So we'll parse a scene's nodes and add some objects to the buttons and
    // assign collision objects from one node to another based on the names of
    // the objects.
    NSString *plist = [[NSBundle mainBundle] pathForResource:list ofType:@"plist"];
    
    //so this is the GameWorld.plist
    NSArray *roomArray = [[NSArray alloc] initWithContentsOfFile:plist];
    
    if(roomArray == nil)
    {
        NSLog(@"No rooms to load in virtual environment");
        return scene;
    }
    
    for (SCNNode *nextRoom in roomArray)
    {
        NSLog (@"Loading Room %@", nextRoom);
        
        // Build a list for collision nodes found in the dae scene and a list
        // for geometry nodes found in the scene
        NSMutableArray *collisionNodes = [[NSMutableArray alloc] init];
        NSMutableArray *geometryNodes = [[NSMutableArray alloc] init];
        
        // Make a parent node for each room in the plist
        SCNNode *roomNode = [SCNNode node];
        roomNode.name = [nextRoom description];
        
        // Get the dae to parse and add to the roomNode
        NSString *sceneName = [NSString stringWithFormat:@"%@%@%@", @"models.scnassets/", nextRoom, @".dae"];
        SCNScene *roomScene = [SCNScene sceneNamed:sceneName];
        
        roomScene.rootNode.name = sceneName;
        
        // Figure out what nodes are in the scene.
        for (SCNNode *node in roomScene.rootNode.childNodes)
        {
            NSString *nodeName = node.name;
            if( [nodeName containsString:@"Collision"] )
            {
                // Found a collision node based on the name collision nodes are simple box
                // geometries that fit around a more complex visually interesting mesh.
                [collisionNodes addObject:node];
            }
            else
            {
                // Object found isn't a collision node so it must be scenery.
                [geometryNodes addObject:node];
            }
        }
        
        // Get geometry nodes into scene
        if(geometryNodes.count > 0)
        {
            for (SCNNode *node in geometryNodes)
            {
                // Add all of the nodes that were not collision to the room
                [roomNode addChildNode:node];
            }
        }
        
        // Combine collision nodes in the scene and add them to their respective geometry nodes
        if (collisionNodes.count > 0)
        {
            // Add collision to scene by taking the nodes in the collisionNodes list
            // and then attach them to the geo node of the same name without @"Collision"
            // they are attached as physicsShapes and then set to static bodies so they
            // don't move.
            SCNNode *collisionNodeGroup = [[SCNNode alloc] init];
            for(SCNNode *node in collisionNodes)
            {
                [collisionNodeGroup addChildNode:node];
            }
            
            SCNPhysicsShape *physicsShape = [SCNPhysicsShape shapeWithNode:collisionNodeGroup
                                                                   options:@{SCNPhysicsShapeTypeKey:SCNPhysicsShapeTypeConvexHull,
                                                                             SCNPhysicsShapeKeepAsCompoundKey:@YES}];
            SCNPhysicsBody *physicsBody = [SCNPhysicsBody staticBody];
            physicsBody.physicsShape = physicsShape;
            
            [physicsBody setContactTestBitMask:SCNPhysicsCollisionCategoryAll];
            
            roomNode.physicsBody = physicsBody;
        }
        
        // After combining scenery with collision add the room node to the scene's root node
        [scene.rootNode addChildNode:roomNode];
    }
    return scene;
}

+ (NSMutableArray*)setupLightsInScene:(SCNScene*)scene
{
    NSMutableArray *_lights = [[NSMutableArray alloc] init];
    
    SCNShadowMode shadowMode = SCNShadowModeDeferred;
    
    for (SCNNode *node in scene.rootNode.childNodes)
    {
        for(SCNNode * n in node.childNodes)
        {
            if([n.name containsString:@"Light"])
            {
                // Create a new light node.
                SCNNode * dLightNode = [SCNNode node];
                dLightNode.name = [n.name stringByAppendingString:@"-Light"];
                
                dLightNode.light = [SCNLight light];
                
                dLightNode.position = n.position;
                dLightNode.eulerAngles = n.eulerAngles;
                
                dLightNode.light.type = SCNLightTypeSpot;
                
                dLightNode.light.color = [UIColor colorWithWhite:0.5 alpha:1.0];
                dLightNode.light.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.1];
                
                dLightNode.light.shadowMode = shadowMode;
                dLightNode.light.castsShadow = YES;
                
                dLightNode.light.zNear = 2.0; // Height from ceiling to floor seems to be a few meters.
                dLightNode.light.zFar = 10.0; // 10.0 (~meters) seems to be plenty far.
                
                dLightNode.light.orthographicScale = 6.5; // Larger fills the room, but starts to look bad.
                
                [_lights addObject:dLightNode];
                [scene.rootNode addChildNode:dLightNode];
            }
        }
    }
    return _lights;
}

@end
