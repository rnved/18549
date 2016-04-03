#import "LXCBViewController.h"

@interface LXCBViewController ()
@end

@implementation LXCBViewController

- (void)loadView {
  CGRect frame = [[UIScreen mainScreen] applicationFrame];
  frame.origin = CGPointZero;

  self.view = [[UIView alloc] initWithFrame:frame];
  self.view.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];

  self.label = [[UILabel alloc] initWithFrame:self.view.bounds];
  self.label.font = [UIFont fontWithName:@"AmericanTypewriter" size:24];
  self.label.text = @"Perception";
  self.label.backgroundColor = [UIColor clearColor];
  self.label.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];;
  [self.view addSubview:self.label];
    
  UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
  [button setTitle:@"Connect to BLE Module" forState:UIControlStateNormal];
  [button sizeToFit];
  button.center = CGPointMake(320/2, 60);
  [button addTarget:self action:@selector(buttonPressed:)
   forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:button];
}

- (void)viewDidLayoutSubviews {
  [self.label sizeToFit];
  self.label.center = CGPointMake(CGRectGetMidX(self.view.bounds),
                                  CGRectGetMidY(self.view.bounds));
}

- (void)buttonPressed:(UIButton *)button {
    NSLog(@"Button Pressed");
}

- (void)centralDidConnect {
  // Pulse the screen blue.
  [UIView animateWithDuration:0.1
                   animations:^{
                     self.view.backgroundColor = [UIColor blueColor];
                   }
                   completion:^(BOOL finished) {
                     [UIView animateWithDuration:0.1
                                      animations:^{
                                        self.view.backgroundColor =
                                            [UIColor colorWithWhite:0.2 alpha:1.0];
                                      }];
                   }];
}

- (void)centralDidDisconnect {
  // Pulse the screen red.
  [UIView animateWithDuration:0.1
                   animations:^{
                     self.view.backgroundColor = [UIColor redColor];
                   }
                   completion:^(BOOL finished) {
                     [UIView animateWithDuration:0.1
                                      animations:^{
                                        self.view.backgroundColor =
                                        [UIColor colorWithWhite:0.2 alpha:1.0];
                                      }];
                   }];
}


@end
