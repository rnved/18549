/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import <SceneKit/SceneKit.h>

NSString* NSStringFromSCNVector3(SCNVector3 vector);

@interface SCNTools : NSObject

#pragma mark - Math and Transforms

+ (SCNVector3) addVector:(SCNVector3)a toVector:(SCNVector3) b;
+ (SCNVector3) subtractVector:(SCNVector3)b fromVector:(SCNVector3) a;

+ (float) vectorMagnitude:( SCNVector3 ) vectorA;
+ (SCNVector3)normalizedVector:(SCNVector3)vectorA;

+ (float) distanceFromVector:( SCNVector3 ) vectorA toVector: ( SCNVector3 ) vectorB;
+ (SCNVector3) directionFromVector:( SCNVector3 ) vectorA toVector: ( SCNVector3 ) vectorB;

+ (SCNVector3) multiplyVector:( SCNVector3 ) vectorA byFloat: ( float ) factor;
+ (SCNVector3) multiplyVector:(SCNVector3)vector bySCNMatrix4:(SCNMatrix4)matrix;
+ (SCNVector3) divideVector:( SCNVector3 ) vectorA byDouble: ( double ) value;

+ (float) dotProduct:(SCNVector3)vectorA andVector:(SCNVector3)vectorB;
+ (float) angleBetweenVector:(SCNVector3)vectorA andVector:(SCNVector3)vectorB;

+ (SCNVector3)capSCNVector3Length:(SCNVector3)vector atFloat:(float) length;

+ (void)logSCNVector3:(SCNVector3)vector;
+ (void)logSCNVector4:(SCNVector4)vector;
+ (void)logSCNMatrix4:(SCNMatrix4)matrix;
+ (void)logGLKMatrix4:(GLKMatrix4)matrix;

+ (SCNVector3) getPositionFromTransform:(SCNMatrix4)m;
+ (SCNVector3) getWorldPos:(SCNNode *)n;
+ (SCNVector3) vectorFromNode:(SCNNode *)fromNode toNode:(SCNNode*)toNode;
+ (float) distancefromNode:(SCNNode *)fromNode toNode:(SCNNode*)toNode;

+ (SCNVector3) getLookAtVectorOfNodeLocal:(SCNNode*)n;
+ (SCNVector3) getLookAtVectorOfNode:(SCNNode*)n;

+ (SCNVector3) crossProductOfSCNVector3:(SCNVector3)vectorA with:(SCNVector3)vectorB;
+ (SCNMatrix4) isolateAxisRotationFromSCNMatrix4:(SCNMatrix4)rotationMatrix axis:(SCNVector3)axis orthoVector:(SCNVector3)orthoVector;

+ (float)randf;
+ (SCNMatrix4) isolateRotationFromSCNMatrix4:(SCNMatrix4)matrix;
+ (SCNMatrix4) convertSTTrackerPoseToSceneKitPose:(GLKMatrix4)stTrackerPose;

#pragma mark - Object Creation
+(SCNScene*) loadSceneFromPlist:(NSString*)list;
+(NSMutableArray*) setupLightsInScene:(SCNScene*)scene;
@end