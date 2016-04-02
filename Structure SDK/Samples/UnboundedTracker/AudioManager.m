/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "AudioManager.h"

#import <AVFoundation/AVFoundation.h>

@implementation AudioManager
AVAudioEngine *audioEngine;
NSMutableDictionary *playNodeDictionary;
NSMutableDictionary *soundBufferDictionary;

AVAudioPlayerNode* _lastNode;

static AudioManager* _sharedAudioManager = nil;

+(AudioManager*)sharedAudioManager
{
    @synchronized([AudioManager class])
    {
        if (!_sharedAudioManager)
        {
            return [[self alloc] init];
        }
        return _sharedAudioManager;
    }
    return nil;
}

+(id)alloc
{
    @synchronized([AudioManager class])
    {
        NSAssert(_sharedAudioManager == nil, @"Attempted to allocate a second instance of a singleton.");
        _sharedAudioManager = [super alloc];
        return _sharedAudioManager;
    }
    return nil;
}

-(id)init
{
    self = [super init];
    if (self)
    {
        _lastNode = nil;
        
        // Create audio engine to play sounds
        audioEngine = [[AVAudioEngine alloc]init];
        
        // Store audioNodes to play in a dictionary
        playNodeDictionary = [[NSMutableDictionary alloc] init];
        soundBufferDictionary = [[NSMutableDictionary alloc] init];
        
        // Read in a list of sounds to play through the audio nodes in the dictionary
        NSString *soundfxPath = [[NSBundle mainBundle] pathForResource:@"SoundFX" ofType:@"plist"];
        NSMutableArray *soundArray = [[NSMutableArray alloc] initWithContentsOfFile:soundfxPath];
        
        for(NSString* soundName in soundArray)
        {
            // Get a file to load into buffer
            NSString *path =[NSString stringWithFormat:@"Sounds/%@", soundName];
            NSURL *aURL = [NSURL URLWithString:[[NSBundle mainBundle] pathForResource:path ofType:@"caf"]];
            AVAudioFile *aFile = [[AVAudioFile alloc] initForReading:aURL error:nil];
            
            // Read file to buffer
            AVAudioPCMBuffer *aBuff = [[AVAudioPCMBuffer alloc] initWithPCMFormat:[aFile processingFormat] frameCapacity:(unsigned int)[aFile length]];
            [aFile readIntoBuffer:aBuff error:nil];
            
            // Make a node per sound
            AVAudioPlayerNode *aNode = [[AVAudioPlayerNode alloc] init];
            
            // Attach the node to audio engine first
            [audioEngine attachNode:aNode];
            
            // Assign format to node
            [audioEngine connect:aNode to:[audioEngine mainMixerNode] format:[aBuff format]];
            
            // Assign the node to the dictionary to make it easier to find again
            playNodeDictionary[soundName] = aNode;
            soundBufferDictionary[soundName] = aBuff;
        }
        
        [[NSNotificationCenter defaultCenter] addObserver: self
            selector:@selector(handleAudioConfigChange:)
            name:AVAudioEngineConfigurationChangeNotification
            object:audioEngine];
        
    }
    return self;
}

-(void)handleAudioConfigChange:(NSNotification*)notification
{
//From Apple:
//    When the audio engine’s I/O unit observes a change to the audio input or output hardware’s channel count or sample rate,
//    the audio engine stops, uninitializes itself, and issues this notification.

//We've found that sometimes, unexpectedly, the audio engine will not be running when we attempt to play audio
// on it. This can cause a crash, and may be because there was a config change.
    
    NSLog(@"AUDIO ENGINE: handleAudioConfigChange");
}

-(void)startAudioEngine
{
    NSError *error;
    BOOL audioStartResult = [audioEngine startAndReturnError:&error];
    if (!audioStartResult)
    {
        NSLog(@"AUDIO ENGINE Start Error: %@", error);
    }
}

-(void)stopAudioEngine
{
    [audioEngine pause];
}

#pragma mark - playing and stopping audio

-(void)stopLastAudio
{
    // Occasionally, this can get called if the audio engine is not running.
    if (![audioEngine isRunning]) {
        return;
    }
    
    if(_lastNode != nil)
    {
        [_lastNode stop];
    }
}

// A special audio play function which only allows one sound to play at a time.
-(void)playEffect:(NSString*)key
{
    [self playAudio:key interruptAudio:NO];
}

-(void)playAudio:(NSString*)key interruptAudio:(BOOL)interrupt
{
    // Occasionally, this can get called if the audio engine is not running.
    if (![audioEngine isRunning]) {
        NSLog(@"AUDIO ENGINE: cancelled play because engine is not running.");
        return;
    }
    
    if (interrupt)
        [self stopLastAudio];
    
    _lastNode = playNodeDictionary[key];
    
    [_lastNode scheduleBuffer:soundBufferDictionary[key] atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionHandler:nil];
    [_lastNode play];
}

@end
