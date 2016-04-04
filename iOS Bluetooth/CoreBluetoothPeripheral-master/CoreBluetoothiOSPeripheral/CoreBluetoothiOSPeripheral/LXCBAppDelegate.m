#import "LXCBAppDelegate.h"
#import "LXCBPeripheralServer.h"
#import "LXCBViewController.h"
#import "UUIDs.h"

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
  self.peripheral.serviceName = SERVICE_NAME;
  self.peripheral.serviceUUID = [CBUUID UUIDWithString:SERVICE_UUID];
  self.peripheral.vb1UUID = [CBUUID UUIDWithString:VB1_UUID];
  self.peripheral.vb2UUID = [CBUUID UUIDWithString:VB2_UUID];
  self.peripheral.vb3UUID = [CBUUID UUIDWithString:VB3_UUID];
  self.peripheral.vb4UUID = [CBUUID UUIDWithString:VB4_UUID];

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

- (void)peripheralServer:(LXCBPeripheralServer *)peripheral
            centralDidSubscribe:(CBCentral *)central
                chosenCharacteristic:(CBCharacteristic *) characteristic {
  NSString* data = nil;
  if([characteristic.UUID.UUIDString isEqual:VB1_UUID]) {
      data = @"Vibe 1";
  } else if ([characteristic.UUID.UUIDString isEqual:VB2_UUID]) {
      data = @"Vibe 2";
  } else if ([characteristic.UUID.UUIDString isEqual:VB3_UUID]) {
      data = @"Vibe 3";
  } else if ([characteristic.UUID.UUIDString isEqual:VB4_UUID]) {
      data = @"Vibe 4";
  } else {
      data = @"Not a matching characteristic";
  }
    
  [self.peripheral sendToSubscribers:[data dataUsingEncoding:NSUTF8StringEncoding]
            chosenCharacteristic:characteristic];
  
  [self.viewController centralDidConnect];
}

- (void)peripheralServer:(LXCBPeripheralServer *)peripheral centralDidUnsubscribe:(CBCentral *)central {
  [self.viewController centralDidDisconnect];

}

@end
