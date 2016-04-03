/*
  This file is part of the Structure SDK.
  Copyright © 2015 Occipital, Inc. All rights reserved.
  http://structure.io
*/

@interface LocalStoreHelper : NSObject {
	NSDictionary* storeDictionary;
	NSString* fileName;
    
    BOOL isExistingUser;
}

@property (nonatomic, retain) NSDictionary* storeDictionary;
@property (nonatomic, retain) NSString* fileName;

- (id)initWithUserId:(NSNumber*)userId;
- (void)saveLocalStore;
- (void)loadLocalStore;
- (void)setValue:(id)val forKey:(id)key;
- (id)objectForKey:(NSString*)key;
- (BOOL)isExistingUser;
+ (LocalStoreHelper*)globalInstance;

@end
