/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "SCNTools.h"

#import "GameData.h"

const float WARP_MAX_LENGTH = 15.0;
const float WARP_MIN_LENGTH = 2.0;
const float WARP_MOVEMENT_TIME = 0.9;

@interface Player ()
{
    GameData* _gameData;
    
    SCNMatrix4 _previousTrackerTransform;
    
    SCNNode* _raycastObject;
    bool _isGrabPossible;
    bool _isHoldingObject;
    bool _hasHeldObject;
    
    // Used to apply movement velocity of the kinematic body to the dynamic body when it's released
    // back into the rootNode
    SCNVector3 _attachedObjectVelocity;
    
    // Various switches for grabbing and warping.
    //  Often needed to communicate state between threads (UI/main versus SceneKit)
    bool _isCameraAllowedToGrab;
    bool _isCameraAllowedToWarp;
    bool _isActionButtonPressed;
    bool _isWarpPossible;
    bool _isWarpEnabled;
    bool _isWarping;
    bool _shouldStartWarp;
    bool _isWalking;
    float _walkSpeed;

    SCNVector3 _warpVector;
    float _warpFinishTime;
    SCNNode *_warpPylon;
    
    bool _warpButtonFirstPress;
    
    // Whether we should release the object. Used for inter-thread communication.
    bool _releaseGrabbedObject;
    
    // LastGrabbed node required to avoid physics tick bug.
    SCNNode* _lastGrabbedObject;
    
    // Trying to maintain some transform to set the grabbed object's transform to avoid
    // physics tick bug.
    SCNNode* _grabbedObjectReference;
}
@end

@implementation Player

/*
 We use a hierarchy of SCNNodes to define our player. From base to tip:
 - Capsule is the main body, used as a physics collider for objects in the scene.
    The capsule only moves horizontally.
 - HeightNode moves up and down with the tracked height of the player's viewpoint
    The heightNode only moves vertically.
 - PanRotationNode is moved when the user pans the view with touches.
    When the view is locked, the PanRotationNode compensates for the player's tracked yaw
    in the real world.
    The panRotationNode only rotates around the vertical (y) axis (yaw).
 - POV Node has the player's camera attached to it, and aligns its rotation according
    to the tracker. It also has a yaw component, in addition to the panRotationNode.
*/

// Create Player Capsule, this uses setVelocity to chase after the navGuide but will stop
// at physics obstacles to obey interactive limits.
-(id) initWithGameData:(GameData*)gameData
{
    self = [super init];
    if (self)
    {
        _gameData = gameData;
        
        self.playerNode = [SCNNode node];
        self.playerNode.name = @"PlayerNode";
        
        // Create player node hierarchy:
        SCNCapsule *capsuleGeo;
        capsuleGeo = [SCNCapsule capsuleWithCapRadius: 0.4 height: 4.0];
        [[capsuleGeo firstMaterial] setTransparency:0.0f];
        [[capsuleGeo firstMaterial] setWritesToDepthBuffer:NO];
        [[capsuleGeo firstMaterial] setReadsFromDepthBuffer:NO];
        [self setCapsule:[SCNNode nodeWithGeometry:capsuleGeo]];
        [self.capsule setName:@"capsuleNode"];
        [self.capsule setGeometry:capsuleGeo];
        
        // The capsule is actually pushed through the world by a velocity rather than just having
        // it's position set to the tracker. This is how we keep the player's in-game presence
        // contained by the game's obstacles like walls and closed doors.
        SCNPhysicsShape *capPhysShape = [SCNPhysicsShape shapeWithGeometry:capsuleGeo options:nil];
        [self.capsule setPhysicsBody:[SCNPhysicsBody dynamicBody]];
        [self.capsule.physicsBody setPhysicsShape:capPhysShape];
        [self.capsule.physicsBody setMass: 70];
        [self.capsule.physicsBody setDamping: 0];
        [self.capsule.physicsBody setFriction: 0];
        [self.capsule.physicsBody setRestitution: 0];
        [self.capsule.physicsBody setVelocityFactor:SCNVector3Make(1.0, 0.0, 1.0)];
        [self.capsule.physicsBody setAngularVelocityFactor:SCNVector3Make(0, 0, 0)];
        [self.capsule.physicsBody setContactTestBitMask:SCNPhysicsCollisionCategoryAll];
        [self setAllowMovement:YES];
        [_gameData.view.scene.rootNode addChildNode:self.capsule];
        [_gameData.raycastIgnoredObjects addObject:self.capsule];
        
        // Intermediate node between capsule and panRotationNode
        // that varies height
        [self setHeightNode:[SCNNode node]];
        [self.heightNode setName:@"heightNode" ];
        [self.heightNode setPosition:SCNVector3Make(0, 1.5, 0)];
        [self.capsule addChildNode:self.heightNode];
        [_gameData.raycastIgnoredObjects addObject:self.heightNode];
        
        // Camera rotation
        [self setPanRotationNode:[SCNNode node]];
        [self.panRotationNode setName:@"panRotationNode"];
        [self.heightNode addChildNode:self.panRotationNode];
        [_gameData.raycastIgnoredObjects addObject:self.panRotationNode];
        
        // Create the Point of View node, which is the node from which the
        // viewpoint is rendered. This node has its XYZ position updated
        // by the movement of the capsule, and its rotation updated by the tracker
        [self setPov:[SCNNode node]];
        [self.pov setName:@"povCamera"];
        [self.panRotationNode addChildNode:self.pov];
        [_gameData.raycastIgnoredObjects addObject:self.pov];
        
        // The camera in the pov
        [self.pov setCamera:[SCNCamera camera]];
        [self.pov.camera setZFar:1000];
        [self.pov.camera setZNear:0.01];
        [self.pov.camera setYFov:80];
        
        // Personal light for the player
        self.pov.light = [SCNLight light];
        [self.pov.light setName:@"freeCameraLight"];
        [self.pov.light setAttenuationStartDistance:1.0];
        [self.pov.light setAttenuationEndDistance:1.5];
        [self.pov.light setAttenuationFalloffExponent:2.0];
        [self.pov.light setSpotInnerAngle:360];
        [self.pov.light setSpotOuterAngle:360];
        
        //Dust particles to demonstrate positional tracking
        SCNParticleSystem *dust = [SCNParticleSystem particleSystemNamed:@"Dust" inDirectory:nil];
        [self.pov addParticleSystem:dust];
        
        // Navigation waypoint (warp).
        [self setWarpPoint:[SCNNode node]];
        [self.warpPoint setName:@"waypoint"];
        [_gameData.view.scene.rootNode addChildNode:self.warpPoint];
        [_gameData.raycastIgnoredObjects addObject:self.warpPoint];
        
        // Warp point visual representation
        _warpPylon = [SCNNode node];
        [_warpPylon setPosition:SCNVector3Make(0.0, 0.5, 0)];
        [_warpPylon setRotation:SCNVector4Make(1.0, 0.0, 0.0, M_PI)];
        [_warpPylon setScale:SCNVector3Make(1, 1, 1)];
        SCNGeometry *pyramid = [SCNPyramid pyramidWithWidth:0.2 height:0.5 length:0.2];
        [_warpPylon setName:@"@waypointPyramid"];
        [_warpPylon setGeometry:pyramid];
        [[[[_warpPylon geometry] firstMaterial] diffuse] setContents:[UIColor yellowColor]];
        [self.warpPoint addChildNode:_warpPylon];
        [self.warpPoint setHidden:YES];
        [_gameData.raycastIgnoredObjects addObject:_warpPylon];
        
        // We can move faster or slower in the virtual world than in the real world, this scaling
        // of movement is handled here.
        _translationScaleFactor.x = 2.5;
        _translationScaleFactor.y = 1.0;
        _translationScaleFactor.z = 2.5;

        // Ray cast pointer is the point in the world that the ray cast is hitting that's not a grabbable.
        self.raycastPointer = [SCNNode nodeWithGeometry:[SCNBox boxWithWidth:0.2 height:0.3 length:0.4 chamferRadius:0]];
        [self.raycastPointer.geometry.firstMaterial.diffuse setContents:[UIColor redColor]];
        [self.raycastPointer.geometry.firstMaterial setTransparency:0.1];
        [self.raycastPointer.geometry.firstMaterial setDoubleSided:NO];
        [self.raycastPointer setHidden:YES];
        [self.raycastPointer setName:@"raycastPointer"];
        [_gameData.view.scene.rootNode addChildNode:self.raycastPointer];

        // ---------- Grab objects
        // This is used to keep the grabbed object from clipping too deeply inside of an object
        // so it's using object centers, actually using physics would require more than this
        // way too much time to try to fix sceneKit physics.
        // adding in reference objects to get transforms from.
        
        // Grab reference is the object that the grabbed object is moved to when grabbed
        SCNGeometry *refGeo = [SCNTorus torusWithRingRadius:2.0 pipeRadius:0.05];
        self.grabReference = [SCNNode nodeWithGeometry:refGeo];
        [self.grabReference.geometry.firstMaterial.diffuse setContents:[UIColor blueColor]];
        [self.grabReference.geometry.firstMaterial setTransparency:0.25];
        [self.grabReference.geometry.firstMaterial setDoubleSided:NO];
        [self.grabReference setHidden:YES];
        [self.grabReference setName:@"grabReference"];
        [_gameData.view.scene.rootNode addChildNode:self.grabReference];
        [_gameData.raycastIgnoredObjects addObject:self.raycastPointer];
        [_gameData.raycastIgnoredObjects addObject:self.grabReference];
        
        // This is an empty object used to retain a transform between node parenting.
        // This is used to reduce the twitchyness of nodes when it's parent is changed.
        // The grab system could be more simple, but there are strange scenekit bugs
        // and this is being used to work around...
        _grabbedObjectReference = [SCNNode node];
        [_grabbedObjectReference.geometry.firstMaterial setTransparency:0.5];
        [_gameData.view.scene.rootNode addChildNode:_grabbedObjectReference];
        [_gameData.raycastIgnoredObjects addObject:_grabbedObjectReference];
        // ---------- / Grab objects
        
        // Add self to the world.
        [_gameData.raycastIgnoredObjects addObject:self.playerNode];
        [_gameData.view.scene.rootNode addChildNode:self.playerNode];
        
        // Touch rotation tracking.
        self.playerPanNode = [SCNNode node];
        self.playerPanNode.name = @"playerPanNode";
        [_gameData.view.scene.rootNode addChildNode:self.playerPanNode];
        [_gameData.raycastIgnoredObjects addObject:self.playerPanNode];
        
        _isWarpEnabled = NO;
        _isActionButtonPressed = NO;
        _previousTrackerTransform = SCNMatrix4Identity;
        self.startRoom = 1; //TODO: set to 2 to start in the second room.

        [self reset];
    }
    return self;
}

-(void) reset
{
    [self releaseObject];
    _isWalking = NO;
    
    self.pointAtObject = nil;
    
    _warpButtonFirstPress = NO;
    
    [self.capsule.physicsBody setType:SCNPhysicsBodyTypeKinematic];
    
    float desiredYaw = M_PI/2.0;
    if (self.startRoom == 2)
    {
        [self.capsule setPosition:SCNVector3Make(-30.0, 0.0, 0.0)];
    }
    else // Default game start
    {
        [self.capsule setPosition:SCNVector3Make(5.0, 0.0, 1.5)];
    }
    float currentLocalYaw = atan2(self.panRotationNode.presentationNode.transform.m31, self.panRotationNode.presentationNode.transform.m33);
    float currentWorldYaw = atan2(self.pov.presentationNode.worldTransform.m31, self.pov.presentationNode.worldTransform.m33);
    [self.panRotationNode setEulerAngles:SCNVector3Make(0, currentLocalYaw + (desiredYaw - currentWorldYaw), 0)];
    
    [self.capsule.physicsBody setType:SCNPhysicsBodyTypeDynamic];
    [self.capsule.physicsBody setVelocity:SCNVector3Zero];
    
    [self.playerPanNode setTransform:SCNMatrix4Identity];
    [self.pov setTransform:SCNMatrix4Identity];
    [self.warpPoint setHidden:YES];
}

-(void) jumpToLab
{
    self.startRoom = 2;
    [self reset];
}

-(void) updateWithTrackerPose:(const TrackerUpdate&) trackerUpdate locked:(BOOL)isLocked deltaTime:(float)time;
{
    // Get most recent pose
    GLKMatrix4 stTrackerPose = trackerUpdate.cameraPose;
    
    // We hold references to the nodes here as that seemed to reduce odd SceneKit updating behaviour.
    SCNNode *heightNode = self.heightNode;
    SCNNode *panRotationNode = self.panRotationNode;
    SCNNode *playerPanNode = self.playerPanNode;
    SCNNode *povCamera = self.pov;

    // Apply the translation scale factor (column major)
    stTrackerPose.m30 *= _translationScaleFactor.x;
    stTrackerPose.m31 *= _translationScaleFactor.y;
    stTrackerPose.m32 *= _translationScaleFactor.z;
    
    // Convert to SceneKit camera pose
    SCNMatrix4 currentTrackerTransform = [SCNTools convertSTTrackerPoseToSceneKitPose:stTrackerPose];
    
    // Isolate rotation of camera from translation
    // Isolate pan Rotation (Y) from other rotations
    
    SCNMatrix4 currIsolateRot = [SCNTools isolateRotationFromSCNMatrix4:currentTrackerTransform];
    float currTrackerPanAngle = atan2(currIsolateRot.m31, currIsolateRot.m33);
    
    SCNMatrix4 newPanMatrix = SCNMatrix4MakeRotation(currTrackerPanAngle, 0, 1, 0);
    bool isInvertible = NO;
    SCNMatrix4 lastPanMatrixINV = SCNMatrix4FromGLKMatrix4(GLKMatrix4Invert(SCNMatrix4ToGLKMatrix4(playerPanNode.transform), &isInvertible));
    SCNMatrix4 panDelta = SCNMatrix4Mult(newPanMatrix, lastPanMatrixINV);
    SCNMatrix4 panDeltaINV = SCNMatrix4FromGLKMatrix4(GLKMatrix4Invert(SCNMatrix4ToGLKMatrix4(panDelta), &isInvertible));
    playerPanNode.transform = newPanMatrix;
    
    povCamera.transform = currIsolateRot;
    
    // If we have at least one finger on the device, it is "panning" we cancel out any tracker
    // movement during this time, making a finger on the device act as a "view lock"
    if (isLocked)
    {
        //update the transform of panRotationNode to offset any rotation due to the tracker.
        panRotationNode.transform = SCNMatrix4Mult(panRotationNode.transform, panDeltaINV);
    }
    
    SCNVector3 instantVelocity = SCNVector3Zero;
    
    // Movement from Tracker
    SCNVector3 newDeltaPos = SCNVector3Zero;
    
    // Get the change in position of the navigation node
    SCNVector3 prevPosition = [SCNTools getPositionFromTransform:_previousTrackerTransform];
    SCNVector3 currentPosition = [SCNTools getPositionFromTransform:currentTrackerTransform];
    
    if (trackerUpdate.couldEstimatePose)
    {
        SCNVector3 deltaPosition = [SCNTools subtractVector:prevPosition fromVector:currentPosition];
        
        // Need to rotate the delta vector (change in tracker position) by the rotation
        // of the panRotationNode (which is caused by pan rotations)
        SCNVector4 curPan = panRotationNode.rotation;
        GLKMatrix4 rotMatGLK = SCNMatrix4ToGLKMatrix4(SCNMatrix4MakeRotation(curPan.w, curPan.x, curPan.y, curPan.z));
        GLKVector3 deltaPosGLK = SCNVector3ToGLKVector3(deltaPosition);
        newDeltaPos = SCNVector3FromGLKVector3(GLKMatrix4MultiplyVector3(rotMatGLK, deltaPosGLK));
        
        // Fix 0.01 with deltaTime
        SCNVector3 delta = [SCNTools divideVector:newDeltaPos byDouble:time];

        // View locking prevents movement in x & z
        if (isLocked)
        {
            delta.x = 0;
            delta.z = 0;
        }
        
        instantVelocity = [SCNTools addVector:delta toVector:instantVelocity];
        _previousTrackerTransform = currentTrackerTransform;
    }
    
    // Warping Movement
    if (_isWarping)
    {
        if (_warpFinishTime > CACurrentMediaTime())
        {
            if(_shouldStartWarp)
            {
                SCNVector3 _warpStartPosition = [SCNTools getWorldPos:self.capsule];
                _warpStartPosition.y = 0;
                SCNVector3 _warpEndPosition = [SCNTools getWorldPos:self.warpPoint];
                _warpVector = [SCNTools subtractVector:_warpStartPosition fromVector:_warpEndPosition];
                _warpVector = [SCNTools capSCNVector3Length:_warpVector atFloat:WARP_MAX_LENGTH];
                
                [_warpPylon.geometry.firstMaterial.diffuse setContents:[UIColor greenColor]];

                // Play warp noise
                _shouldStartWarp = NO;
            }
            
            float easeMagnitude = 4*(0.5 - fabs(0.5 - (_warpFinishTime - CACurrentMediaTime())/WARP_MOVEMENT_TIME));
            SCNVector3 warp = [SCNTools multiplyVector:_warpVector byFloat:easeMagnitude];
            instantVelocity = [SCNTools addVector:warp toVector:instantVelocity];
        }
        else if(_warpFinishTime < CACurrentMediaTime())
        {
            _warpPylon.geometry.firstMaterial.diffuse.contents = [UIColor yellowColor];
            _isWarping = NO;
        }
    }
    
    // Walking movement (holding the walk button)
    SCNMatrix4 playerRotation = [SCNTools isolateRotationFromSCNMatrix4:self.pov.worldTransform];
    
    SCNVector3 forwardVector = SCNVector3Make(0, 0, -1);
    forwardVector = [SCNTools multiplyVector:forwardVector bySCNMatrix4:playerRotation];
    if (_isWalking)
    {
        _walkSpeed = fminf(4.0, _walkSpeed + 9*time);
    }
    else
    {
        _walkSpeed = fmaxf(0.0, _walkSpeed - 15*time);
    }
    instantVelocity.x += _walkSpeed*forwardVector.x;
    instantVelocity.z += _walkSpeed*forwardVector.z;
    
    // Physics object (capsuleNode) does not move in y, the heightNode does
    instantVelocity.y = 0;
    
    if (!self.allowMovement)
    {
        instantVelocity = SCNVector3Make(0,0,0);
    }
    
    [self.capsule.physicsBody setVelocity:instantVelocity];
    
    // Setting height
    if (trackerUpdate.couldEstimatePose)
    {
        [heightNode setPosition:SCNVector3Make(0, currentPosition.y, 0)];
        
        //limit at floor
        const float FLOOR_LIMIT = 0.05f;
        if ([SCNTools getWorldPos:heightNode].y < FLOOR_LIMIT)
        {
            float diff =  FLOOR_LIMIT - [SCNTools getWorldPos:heightNode].y;
            [heightNode setPosition:[SCNTools addVector:heightNode.position toVector:SCNVector3Make(0, diff, 0)]];
        }
    }
    
    if(_releaseGrabbedObject)
    {
        _releaseGrabbedObject = NO;
        [_lastGrabbedObject removeAllActions];
        [_lastGrabbedObject removeAllAnimations];
        [SCNTransaction begin];
        [SCNTransaction setAnimationDuration:1.0];
        [SCNTransaction setCompletionBlock:^{
            [_gameData.view.scene.rootNode addChildNode:_lastGrabbedObject];
            [_lastGrabbedObject.physicsBody setType:SCNPhysicsBodyTypeDynamic];
            [_lastGrabbedObject.physicsBody setVelocity:_attachedObjectVelocity];
        }];
        [_lastGrabbedObject setTransform:_grabbedObjectReference.transform];
        [_lastGrabbedObject.physicsBody resetTransform];
        [_lastGrabbedObject.physicsBody clearAllForces];
        [SCNTransaction commit];
    }
}

-(void) updateUI
{
    // Label setting and reticle settings
    if(_isGrabPossible)
    {
        [self.warpButton setTitle:@"" forState:UIControlStateNormal];
        [self.warpButton setTitle:@"" forState:UIControlStateHighlighted];
        
        if(!_isHoldingObject)
        {
            [self.reticle setReticleStyle:@"canGrab"];
        }
        else
        {
            [self.reticle setReticleStyle:@"hasGrabbed"];
            [self.warpButton setTitle:@"Walk" forState:UIControlStateNormal];
            [self.warpButton setTitle:@"Walking" forState:UIControlStateHighlighted];
        }
        [self.actionButton setTitle:@"Grab" forState:UIControlStateNormal];
        [self.actionButton setTitle:@"Release" forState:UIControlStateHighlighted];
        
    }
    else
    {
        if (!_isCameraAllowedToWarp && !_isCameraAllowedToGrab)
            [self.reticle setReticleStyle:@"disabled"];
        else
            [self.reticle setReticleStyle:@"default"];
     
        
        [self.actionButton setTitle:@"" forState:UIControlStateNormal];
        [self.actionButton setTitle:@"" forState:UIControlStateHighlighted];
        
        if (_isWarpPossible && !_isWalking)
        {
            //!isWalking is to cover a weird case:
            // - the user picks up an object, start walk-button, and then release object.
            [self.warpButton setTitle:@"Warp" forState:UIControlStateNormal];
            [self.warpButton setTitle:@"Warping" forState:UIControlStateHighlighted];
        }
        else
        {
            [self.warpButton setTitle:@"" forState:UIControlStateNormal];
            [self.warpButton setTitle:@"" forState:UIControlStateHighlighted];
        }
    }
    
    if(self.attachedObject == nil && _raycastObject != nil && _isActionButtonPressed && !_isHoldingObject)
    {
        _isHoldingObject = YES;
    }
    else if((self.attachedObject != nil && !_isActionButtonPressed && _isHoldingObject) ||  !_isCameraAllowedToGrab)
    {
        _isHoldingObject = NO;
    }
}

-(void) updateSceneKit
{
    // Keep the player from grabbing things that are too close and don't allow the player to
    // grab things that are way far away
    const float MINIMUM_GRAB_DISTANCE = 0.0;
    const float MAXIMUM_GRAB_DISTANCE = 3.0;
    
    // Update isCameraAllowedToGrab or Warp bool for UI thread
    SCNVector3 lookVec = [SCNTools getLookAtVectorOfNode:self.pov];
    
    // This keeps the objects below the player's feet from getting picked up
    _isCameraAllowedToGrab = [self cameraAllowsGrab:lookVec];
    
    // This keeps the player from warping to their feet
    _isCameraAllowedToWarp = [self cameraAllowsWarp:lookVec];
    
    // Use the sceneView to get an array of objects from the center of the screen
    CGPoint center;
    center.x = _gameData.view.window.bounds.size.width*0.5;
    center.y = _gameData.view.window.bounds.size.height*0.5;
    NSArray *hitResults = [_gameData.view hitTest:center options:nil];
    
    // Keep track of the hit result distances if there's one closer than the max then update
    // the distance to the closer one, once there's no more objects closer then that's the
    // one we grab
    float castRayLength = 0;
    float closestDistance = WARP_MAX_LENGTH;
    
    if (self.attachedObject!=nil)
    {
        _attachedObjectVelocity = [self.attachedObject.physicsBody velocity];
    }
    
    SCNNode *newPointAtObject = nil;
    float newPointAtDistance = 0;
    
    SCNNode *firstBGObject = nil;
    SCNVector3 firstBGPosition;
    
    for (SCNHitTestResult *result in hitResults)
    {
        // Ignore objects in ignored objects array
        if ([_gameData.raycastIgnoredObjects containsObject:result.node])
        {
            continue;
        }
        
        // Ignore ephemeral objects, but not static objects which have mass 0 the magic 0.00000001
        // number comes from a forum about SceneKit where this seems to make a physics object still
        // register collision events but not actually block movement
        if (result.node.physicsBody.mass < 0.00000001 && result.node.physicsBody.mass > 0)
        {
            continue;
        }
        
        SCNVector3 diff = [SCNTools subtractVector:[SCNTools getWorldPos:self.pov] fromVector:result.worldCoordinates];
        castRayLength = [SCNTools vectorMagnitude:diff];
        
        if (newPointAtObject == nil)
        {
            newPointAtObject = result.node;
            newPointAtDistance = castRayLength;
        }
        
        if (firstBGObject == nil && ![_gameData.grabbableObjects containsObject:result.node])
        {
            firstBGObject = result.node;
            firstBGPosition = result.worldCoordinates;
        }
        
        if (castRayLength < closestDistance)
        {
            closestDistance = castRayLength;
            
            _isGrabPossible = (closestDistance > MINIMUM_GRAB_DISTANCE &&
                              closestDistance < MAXIMUM_GRAB_DISTANCE &&
                              [_gameData.grabbableObjects containsObject:result.node] &&
                              _isCameraAllowedToGrab);
            
            _isWarpPossible = !_isWalking &&
                             !_isGrabPossible &&
                             (closestDistance < WARP_MAX_LENGTH &&
                             closestDistance > WARP_MIN_LENGTH &&
                             _isCameraAllowedToWarp);
                            
            if (_isGrabPossible)
            {
                _raycastObject = nil;
                
                if(_isActionButtonPressed)
                {
                    _raycastObject = result.node;
                }
            }
            else
            {
                // Let it go, let it GO...
                _raycastObject = nil;
            }
            
            // Get warp point when you can't grab anything
            if (_isWarpEnabled && _isWarpPossible && !_isGrabPossible && !_isHoldingObject)
            {
                SCNVector3 hitPosition = result.worldCoordinates;
                SCNVector3 nodePosition =[[self.capsule presentationNode] position];
                SCNVector3 towardPlayer = [SCNTools subtractVector:result.worldCoordinates fromVector:nodePosition];
                float towardPlayerLength = [SCNTools vectorMagnitude:towardPlayer];
                SCNVector3 normalizedTowardPlayer = [SCNTools normalizedVector:towardPlayer];
                
                float shortenAmount = 0.25;
                if (towardPlayerLength < 1.5)
                {
                    shortenAmount = 0;
                }
                else if (towardPlayerLength < 3.0)
                {
                    shortenAmount = 0.25*(towardPlayerLength - 1.5)/(3.0 - 1.5);
                }
                
                SCNVector3 shortenedDistanceTowardPlayer = [SCNTools multiplyVector:normalizedTowardPlayer byFloat:shortenAmount];
                SCNVector3 offsetFromWall = [SCNTools addVector:hitPosition toVector:shortenedDistanceTowardPlayer];
                offsetFromWall.y = 0;
                
                // Don't move the warp point while we're warping towards it.
                if (!_isWarping)
                {
                    [self.warpPoint setPosition:offsetFromWall];
                }
                
                if(self.warpPoint.isHidden)
                {
                    [self.warpPoint setHidden:NO];
                }
            }
            else
            {
                if(!_isWarping && !self.warpPoint.isHidden)
                    [self.warpPoint setHidden:YES];
            }
        }
        else if(_isGrabPossible || (!self.warpPoint.isHidden && !(closestDistance < WARP_MAX_LENGTH && closestDistance > WARP_MIN_LENGTH && _isCameraAllowedToWarp)))
        {
            [self.warpPoint setHidden:YES];
            _isWarpPossible = NO;
        }

    }
    
    // Grab update
    // Awkward long list of things to skip the update if you're pointed at
    if(self.attachedObject && firstBGObject)
    {
        // Get the world position of the ray cast in the environment that's not a grabbed object
        // Put the raycast pointer at the cast position
        [self.raycastPointer setPosition:firstBGPosition];
        
        // World position from the grabbed object
        //  update the position of the attached object to
        //  the pointer in the world if it's closer to the camera than
        //  the grab reference position in the world
        SCNVector3 refPosition          = [SCNTools getWorldPos:self.grabReference];
        SCNVector3 povPosition          = [SCNTools getWorldPos:self.pov];
        SCNVector3 deltaToRaycastPoint  = [SCNTools subtractVector:povPosition fromVector:firstBGPosition];
        SCNVector3 deltaToGrabReference = [SCNTools subtractVector:povPosition fromVector:refPosition];
        float magnitudeToWorldPoint     = [SCNTools vectorMagnitude:deltaToRaycastPoint];
        float magnitudeToGrabReference  = [SCNTools vectorMagnitude:deltaToGrabReference];
        
        SCNMatrix4 grabXform = self.grabReference.presentationNode.worldTransform;
        SCNMatrix4 rayXform = self.raycastPointer.presentationNode.worldTransform;
        
        if(magnitudeToWorldPoint > magnitudeToGrabReference)
        {
            [self.attachedObject setTransform:grabXform];
            [_grabbedObjectReference setTransform:grabXform];
        }
        else
        {
            SCNMatrix4 isolateRot = [SCNTools isolateRotationFromSCNMatrix4:grabXform];
            SCNMatrix4 ixform = SCNMatrix4Mult(isolateRot, rayXform);
            [self.attachedObject setTransform: ixform];
            [_grabbedObjectReference setTransform:ixform];
        }
    }

    self.pointAtObject = newPointAtObject;
    self.pointAtDistance = newPointAtDistance;
    
    // Double check to see if we're holding an object if the _raycastObject is nil, then there
    // isn't anything actually being held.
    if(_isHoldingObject && _raycastObject == nil && self.attachedObject == nil)
    {
        _hasHeldObject = NO;
        _isHoldingObject = NO; // Awkward place to set this.
        [self releaseObject];
    }
    
    if(_isHoldingObject && !_hasHeldObject)
    {
        _hasHeldObject = YES;
        [self holdObject];
    }
    else if(!_isHoldingObject && _hasHeldObject)
    {
        _hasHeldObject = NO;
        [self releaseObject];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateUI];
    });
}

// Change the ray cast object's parent to the camera's pov node then set it to kinematic
-(void) holdObject
{
    [self setAttachedObject:_raycastObject];
    [self.attachedObject.physicsBody setType:SCNPhysicsBodyTypeKinematic];
    SCNMatrix4 attachedObjInitialTransform = [self.attachedObject.presentationNode convertTransform:SCNMatrix4Identity toNode:self.pov.presentationNode];
    [self.grabReference setTransform:attachedObjInitialTransform];
    [self.pov addChildNode:self.grabReference];
}

// Parent the attached object to the root node of the scene then set it to dynamic do this in
// the scenekit update thread if you don't then you'll come across a weird bug where nodes
// take a frame and try to rotate back to their matrix identity
-(void) releaseObject
{
    if (!self.attachedObject)
        return;
    _lastGrabbedObject = self.attachedObject;
    [self setAttachedObject:nil];
    _releaseGrabbedObject = YES;
}

// Cut the grab off at the player's feet
- (BOOL)cameraAllowsGrab:(SCNVector3)lookVector
{
    const float GRAB_CUTOFF_ANGLE = M_PI/180.0*30.0;//looking down too low
    float angleBetween = [SCNTools angleBetweenVector:lookVector andVector:SCNVector3Make(0, -1, 0)];
    return angleBetween > GRAB_CUTOFF_ANGLE;
}

// Cut off the warp at the player's feet and when looking too high
- (BOOL)cameraAllowsWarp:(SCNVector3)lookVector
{
    const float LOW_ANGLE  = M_PI/180.0*30.0; //looking down too low
    const float HIGH_ANGLE = M_PI/180.0*110.0; //looking up too high
    float viewAngle = [SCNTools angleBetweenVector:lookVector andVector:SCNVector3Make(0, -1, 0)];
    return viewAngle > LOW_ANGLE && viewAngle < HIGH_ANGLE;
}

// Get button actions from viewcontroller
-(void) actionButtonDown
{
    _isActionButtonPressed = YES;
}

-(void) actionButtonUp
{
    _isActionButtonPressed = NO;
}

-(void) warpButtonDown
{
    if(_isHoldingObject)
    {
        if (!_isWalking)
        {
            _walkSpeed = 0.0;
            _isWalking = YES;
        }
        return;
    }
    
    if(!_isWarping && _isWarpPossible)
    {
        _warpFinishTime = CACurrentMediaTime() + WARP_MOVEMENT_TIME;
        _shouldStartWarp = YES;
        _isWarping = YES;
        
        if(!_warpButtonFirstPress)
        {
            _warpButtonFirstPress = YES;
        }
    }
}

-(void) warpButtonUp
{
    _isWalking = NO;
}

-(void) setWarpEnabled:(BOOL)warpEnabled
{
    _isWarpEnabled = warpEnabled;
    [self.warpButton setHidden:!warpEnabled];
}

-(bool)canGrab
{
    return _isGrabPossible;
}

-(bool)canWarp
{
    return _isWarpPossible;
}

-(bool) warpButtonHasBeenPressed
{
    return _warpButtonFirstPress;
}
@end
