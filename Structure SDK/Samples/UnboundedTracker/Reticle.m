/*
 This file is part of the Structure SDK.
 Copyright © 2015 Occipital, Inc. All rights reserved.
 http://structure.io
 */

#import "Reticle.h"

const BOOL HIDE_RETICLE = NO;

@implementation Reticle

CGRect _rect;
NSDictionary *reticleStyles;
NSString* _currentStyle;

- (id)createReticleStyle:(NSString*)filename
{
    UIImageView* imageview = [[UIImageView alloc] initWithImage:[UIImage imageNamed:filename]];
    // Must set sub-frame to enforce size
    CGRect localRect = _rect;
    localRect.origin.x = 0;
    localRect.origin.y = 0;
    [imageview setFrame:localRect];
    [self.view addSubview:imageview];
    
    return imageview;
}

- (id)initWithFrame:(CGRect)rect
{
    self = [super init];
    if(self)
    {
        _rect = rect;
        self.view = [[UIView alloc] initWithFrame:rect];
        
        CGRect localRect = _rect;
        localRect.origin.x = 0;
        localRect.origin.y = 0;
        
        reticleStyles = @ {
            @"default" : [self createReticleStyle:@"reticle_default.png"],
            @"canGrab" : [self createReticleStyle:@"reticle_can_grab.png"],
            @"hasGrabbed" : [self createReticleStyle:@"reticle_has_grabbed.png"],
            @"disabled" : [self createReticleStyle:@"reticle_disabled.png"]
        };
        
        [self setReticleStyle:@"default"];
    }
    
    return self;
}

-(BOOL)setReticleStyle:(NSString*)style
{
    // Hide all reticleStyles except the current one
    for (id _style in reticleStyles) {
        if (style == _style && !HIDE_RETICLE)
            [reticleStyles[_style] setHidden:NO];
        else
            [reticleStyles[_style] setHidden:YES];
        [reticleStyles[_style] setAlpha:0.9];
    }
        
    _currentStyle = style;
    return NO;
}

@end
