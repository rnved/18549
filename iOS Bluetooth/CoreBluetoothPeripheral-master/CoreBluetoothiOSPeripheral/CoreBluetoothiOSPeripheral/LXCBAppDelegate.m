#import "LXCBAppDelegate.h"
#import "LXCBPeripheralServer.h"
#import "LXCBViewController.h"

@interface LXCBAppDelegate () <LXCBPeripheralServerDelegate>

@property (nonatomic, strong) LXCBPeripheralServer *peripheral;
@property (nonatomic, strong) LXCBViewController *viewController;

@end

@implementation LXCBAppDelegate

- (void)attachUserInterface {
  self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  self.window.backgroundColor = [UIColor whiteColor];

  self.viewController = [[LXCBViewController alloc] init];
  self.window.rootViewController = self.viewController;

  [self.window makeKeyAndVisible];

}


- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  // If the application is in the background state, then we have been
  // woken up because of a bluetooth event. Otherwise, we can initialize the
  // UI.
  NSLog(@"didFinishedLaunching: %@", launchOptions);
  if (application.applicationState != UIApplicationStateBackground) {
    [self attachUserInterface];
  }


  self.peripheral = [[LXCBPeripheralServer alloc] initWithDelegate:self];
  self.peripheral.serviceName = @"Perception";
  self.peripheral.serviceUUID = [CBUUID UUIDWithString:@"6314"];
  //self.peripheral.serviceUUID = [CBUUID UUIDWithString:@"63146596-6BB6-4229-9928-C2F8C3B20C01"];
  self.peripheral.vb1UUID = [CBUUID UUIDWithString:@"420107B0-06BF-40C3-B977-6A0EEEC2A3DC"];
  self.peripheral.vb2UUID = [CBUUID UUIDWithString:@"706E2A15-B476-4096-9D0B-BDAB89F08938"];
  self.peripheral.vb3UUID = [CBUUID UUIDWithString:@"3AA4ED79-F7DF-4F69-98BF-11F69B9E6ED0"];
  self.peripheral.vb4UUID = [CBUUID UUIDWithString:@"E7CA3B78-5857-4841-BA50-38A3F1EDFE75"];

  [self.peripheral startAdvertising];

  return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
  [self.peripheral applicationDidEnterBackground];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
  if (!self.window) {
    [self attachUserInterface];
  }
  [self.peripheral applicationWillEnterForeground];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
}

- (void)applicationWillTerminate:(UIApplication *)application {
  NSLog(@"Application terminating");
  // Cry for help.
  UILocalNotification *notification = [[UILocalNotification alloc] init];
  notification.alertBody = @"I'm dying!";
  notification.alertAction = @"Rescue";
  notification.fireDate = [NSDate date];
  [[UIApplication sharedApplication] scheduleLocalNotification:notification];
}

#pragma mark - LXCBPeripheralServerDelegate

- (void)peripheralServer:(LXCBPeripheralServer *)peripheral centralDidSubscribe:(CBCentral *)central {
  [self.peripheral sendToSubscribers:@[[@"Vibe 1" dataUsingEncoding:NSUTF8StringEncoding],
                                       [@"Vibe 2" dataUsingEncoding:NSUTF8StringEncoding],
                                       [@"Vibe 3" dataUsingEncoding:NSUTF8StringEncoding],
                                       [@"Vibe 4" dataUsingEncoding:NSUTF8StringEncoding]]];
  // TODO: How to do multiple characteristics? 
  [self.viewController centralDidConnect];
}

- (void)peripheralServer:(LXCBPeripheralServer *)peripheral centralDidUnsubscribe:(CBCentral *)central {
  [self.viewController centralDidDisconnect];

}

@end
