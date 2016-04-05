/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "AppDelegate.h"
#import "LXCBPeripheralServer.h"
#import "ViewController.h"
#import "UUIDs.h"

@interface AppDelegate () <LXCBPeripheralServerDelegate>

@property (nonatomic, strong) LXCBPeripheralServer *peripheral;

@end

@implementation AppDelegate

- (void)attachUserInterface {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor whiteColor];
    
    self.viewController = [[ViewController alloc] init];
    self.window.rootViewController = self.viewController;
    
    [self.window makeKeyAndVisible];
    
}


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    /********************* BEGIN BLUETOOTH *********************************/
    // If the application is in the background state, then we have been
    // woken up because of a bluetooth event. Otherwise, we can initialize the
    // UI.
    NSLog(@"didFinishedLaunching: %@", launchOptions);
    
    // Do we need peripheral UI?
    /*if (application.applicationState != UIApplicationStateBackground) {
        [self attachUserInterface];
    }*/
    
    self.peripheral = [[LXCBPeripheralServer alloc] initWithDelegate:self];
    self.peripheral.serviceName = SERVICE_NAME;
    self.peripheral.serviceUUID = [CBUUID UUIDWithString:SERVICE_UUID];
    self.peripheral.vb1UUID = [CBUUID UUIDWithString:VB1_UUID];
    self.peripheral.vb2UUID = [CBUUID UUIDWithString:VB2_UUID];
    self.peripheral.vb3UUID = [CBUUID UUIDWithString:VB3_UUID];
    self.peripheral.vb4UUID = [CBUUID UUIDWithString:VB4_UUID];
    
    [self.peripheral startAdvertising];
    
    /********************** DONT MOVE TO NEXT PART UNTIL CONNECTION CONFIRMED **************/
        
    /********************** BEGIN STRUCTURE *********************************/
    
    // STWirelessLog is very helpful for debugging while your Structure Sensor is plugged in.
    // See SDK documentation for how to start a listener on your computer.
    NSError* error = nil;
    NSString *remoteLogHost = @"128.237.234.196";
    [STWirelessLog broadcastLogsToWirelessConsoleAtAddress:remoteLogHost usingPort:4999 error:&error];
    if (error)
        NSLog(@"Oh no! Can't start wireless log: %@", [error localizedDescription]);

    /*  iOS 9.2+ introduced unexpected behavior: every time a Structure Sensor is
     plugged in to iOS, iOS will launch all Structure SDK apps in the background.
     The apps will not be visible to the user.  This can cause problems since
     Structure SDK apps typically ask the user for permission to use the camera
     when launched.  This leads to the user's first experience with a Structure
     SDK app being:
     1.  Download Structure SDK apps from App Store
     2.  Plug in Structure Sensor to iPad
     3.  Get bombarded with "X app wants to use the Camera" notifications from
         every installed Structure SDK app
     
     Each app has to deal with this problem in its own way.  In the Structure SDK,
     sample apps peacefully exit without causing a crash report.  This also
     has other benefits, such as not using memory.  Note that Structure SDK does
     not support connecting to Structure Sensor if the app is in the background. */
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        NSLog(@"iOS launched %@ in the background.  This app is not designed to be launched in the background so it will exit peacefully.",
              [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"]);
        exit(0);
    }

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    // Override point for customization after application launch.
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        self.viewController = [[ViewController alloc] initWithNibName:@"ViewController_iPhone" bundle:nil];
    } else {
        self.viewController = [[ViewController alloc] initWithNibName:@"ViewController_iPad" bundle:nil];
    }
    self.window.rootViewController = self.viewController;
    [self.window makeKeyAndVisible];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    [self.peripheral applicationDidEnterBackground];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    if (!self.window) {
        [self attachUserInterface];
    }
    [self.peripheral applicationWillEnterForeground];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
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
