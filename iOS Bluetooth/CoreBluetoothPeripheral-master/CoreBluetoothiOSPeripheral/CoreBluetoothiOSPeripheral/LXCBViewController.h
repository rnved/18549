#import <UIKit/UIKit.h>

@interface LXCBViewController : UIViewController

@property (strong) UILabel *label;

- (void)buttonPressed:(UIButton *)button;
- (void)centralDidConnect;
- (void)centralDidDisconnect;

@end
