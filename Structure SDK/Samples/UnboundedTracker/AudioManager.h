/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

@interface AudioManager : NSObject 

+(AudioManager*) sharedAudioManager;

-(void)startAudioEngine;
-(void)stopAudioEngine;

-(void)stopLastAudio;
-(void)playEffect:(NSString*)key;
-(void)playAudio:(NSString*)key interruptAudio:(BOOL)interrupt;

@end
