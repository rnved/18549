/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#import "GameData.h"

@implementation GameData

- (id)init
{
    if (self = [super init])
    {
        // Must initialize any arrays here.
        self.grabbableObjects = [[NSMutableArray alloc] init];
        self.raycastIgnoredObjects = [[NSMutableArray alloc] init];
        return self;
    }
    return nil;
}

@end
