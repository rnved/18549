/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "Joystick.h"

@interface Joystick ()
{
    CADisplayLink* _displayLink;
    UIImageView* _backgroundView;
    UIImageView* _joystickView;
    
    BOOL _isSelected;
    CGPoint _targetJoystickCenter;
    float _Rx, _Ry;
    float _theta;
    float _radius;
    
    CGPoint _centerInView;
}
@end


@implementation Joystick

- (id)initWithFrame:(CGRect)frame backgroundImage:(NSString*)backgroundImageName
                                    joystickImage:(NSString*)joystickImageName
{
    self = [super init];
    if(self)
    {
        self.view = [[UIView alloc] initWithFrame:frame];
        
        _backgroundView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:backgroundImageName]];
        _joystickView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:joystickImageName]];
    
        _Rx = _backgroundView.frame.size.width/2;
        _Ry = _backgroundView.frame.size.height/2;
        
        [self.view addSubview:_backgroundView];
        [self.view addSubview:_joystickView];
        
        [self setSelected:NO];
        [self setEnabled:YES];
        
        _displayLink = nil;
    }
    
    return self;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    _centerInView = [self.view.superview convertPoint:self.view.center toView:self.view];
    
    _backgroundView.center = _centerInView;
    _joystickView.center = _centerInView;
    _targetJoystickCenter = _centerInView;
    
    if(_displayLink == nil)
    {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(animate)];
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if(_displayLink == nil)
    {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(animate)];
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [_displayLink invalidate];
    _displayLink = nil;
}

- (void)setEnabled:(BOOL)enabled
{
    _isEnabled = enabled;
    self.view.userInteractionEnabled = enabled;
    
    if(enabled)
    {
        [UIView animateWithDuration:0.5 animations:^{
            self.view.alpha = 1.0;
        }];
    }
    else
    {
        [UIView animateWithDuration:0.5 animations:^{
            self.view.alpha = 0.0;
        }];
    }
}

- (void)setSelected:(BOOL)isSelected
{
    _isSelected = isSelected;
    if (isSelected)
    {
        [UIView animateWithDuration:0.1 animations:^{
            _backgroundView.alpha = 1.0;
            _joystickView.alpha = 1.0;
        }];
    }
    else
    {
        [UIView animateWithDuration:0.1 animations:^{
            _backgroundView.alpha = 0.5;
            _joystickView.alpha = 0.5;
        }];
    }
}

inline float getThetaFromCGPoints(CGPoint a, CGPoint b)
{
    float diffX = a.x - b.x;
    float diffY = a.y - b.y;
    
    return atan2f(diffY, diffX);
}

inline float getRadiusFromCGPoints(CGPoint a, CGPoint b, float Rx, float Ry)
{
    float diffX = (a.x - b.x)/Rx;
    float diffY = (a.y - b.y)/Ry;
    
    return MIN(sqrtf(diffX*diffX + diffY * diffY), 1.0);
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self setSelected:YES];
    
    UITouch *touch = [touches anyObject];
    [self handleTouchesChange:touch];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    [self handleTouchesChange:touch];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self setSelected:NO];
    _targetJoystickCenter = _centerInView;
}

- (void)handleTouchesChange:(UITouch*)touch
{
    CGPoint touchPoint = [touch locationInView:self.view];
    
    float targetTheta = getThetaFromCGPoints(touchPoint, _centerInView);
    float targetRadius = getRadiusFromCGPoints(touchPoint, _centerInView, _Rx, _Ry);
    
    _targetJoystickCenter = touchPoint;
    _targetJoystickCenter.x = _centerInView.x + _Rx * targetRadius * cos(targetTheta);
    _targetJoystickCenter.y = _centerInView.y + _Ry * targetRadius * sin(targetTheta);
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self setSelected:NO];
    _targetJoystickCenter = _centerInView;
}

- (float)radius
{
    return _radius;
}

- (float)theta
{
    return _theta;
}

- (void) animate
{
    CGPoint nextCenter;
    nextCenter.x = 0.5 * (_joystickView.center.x + _targetJoystickCenter.x);
    nextCenter.y = 0.5 * (_joystickView.center.y + _targetJoystickCenter.y);
    
    _joystickView.center = nextCenter;
    
    _theta = getThetaFromCGPoints(_joystickView.center, _centerInView);
    _radius = getRadiusFromCGPoints(_joystickView.center, _centerInView, _Rx, _Ry);
}

@end
