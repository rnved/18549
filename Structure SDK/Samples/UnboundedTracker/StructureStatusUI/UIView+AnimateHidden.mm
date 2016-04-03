/*
 This file is part of the Structure SDK.
 Copyright © 2015 Occipital, Inc. All rights reserved.
 http://structure.io
 */

#import "UIView+AnimateHidden.h"

#import <objc/runtime.h>
#import <QuartzCore/CALayer.h>

@interface UIView_AnimateHidden_State : NSObject
{
@public
    CGFloat unhiddenAlpha;
    BOOL isAnimating;
    BOOL animatedHiddenEndGoal;
}

+ (UIView_AnimateHidden_State*) stateForView:(UIView*)view;

@end

@implementation UIView_AnimateHidden_State

+ (UIView_AnimateHidden_State*)stateForView:(UIView*)view
{
    static void* key = &key; // The static object address is used as the unique key.
    
    UIView_AnimateHidden_State* state = objc_getAssociatedObject(view, key);
    if (nil == state)
    {
        state = [[UIView_AnimateHidden_State alloc] init];
        objc_setAssociatedObject(view, key, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

- (id)init;
{
    self = [super init];
    isAnimating = NO;
    unhiddenAlpha = 1.0;
    return self;
}

@end

//-----------------------------------------------------
@implementation UIView (AnimateHidden)

- (void) setHidden: (BOOL) shouldBeHidden animated: (BOOL) shouldBeAnimated
{
    [self setHidden:shouldBeHidden animated:shouldBeAnimated animationDuration: .5];
}

- (void) setHidden: (BOOL) shouldBeHidden animated: (BOOL) shouldBeAnimated animationDuration:(float)durationInSeconds;
{
    UIView_AnimateHidden_State *state = [UIView_AnimateHidden_State stateForView:self];

    if (!state->isAnimating && shouldBeHidden == self.hidden)
    {
        //already in desired state
        return;
    }
    
    if (state->isAnimating && (state->animatedHiddenEndGoal != shouldBeHidden || !shouldBeAnimated))
    {
        //cancel existing animation.
        [self.layer removeAllAnimations];
        self.alpha = state->unhiddenAlpha;
        state->isAnimating = NO;
    }
    
    if (!shouldBeAnimated)
    {
        [self setHidden:shouldBeHidden];
        return;
    }
    
    state->isAnimating = YES;
    state->animatedHiddenEndGoal = shouldBeHidden;
    state->unhiddenAlpha = self.alpha;
    
    if (!shouldBeHidden)
        self.alpha = 0.; // Start the unhide animation with as transparent
    [self setHidden:NO]; //want to be unhidden, regardless of the animation.
    
    [ UIView
        animateWithDuration: durationInSeconds
        delay: 0.
        options: shouldBeHidden ? UIViewAnimationOptionCurveEaseIn : UIViewAnimationOptionCurveEaseOut
        animations: ^ {
            self.alpha = shouldBeHidden ? 0 : state->unhiddenAlpha;
        }
        completion: ^ (BOOL b) {
            [self setHidden:shouldBeHidden];
            self.alpha = state->unhiddenAlpha;
            state->isAnimating = NO;
        }
    ];
}

@end
