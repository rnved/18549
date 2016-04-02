/*
 This file is part of the Structure SDK.
 Copyright © 2015 Occipital, Inc. All rights reserved.
 http://structure.io
 */

#import "LocalStoreHelper.h"

static LocalStoreHelper *globalInstance = nil;
#define GlobalInstanceFileName @"local.store"

@implementation LocalStoreHelper

@synthesize storeDictionary;
@synthesize fileName;

- (void)saveLocalStore
{
	NSMutableData *data = [NSMutableData data];
	NSKeyedArchiver *encoder = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
	[encoder encodeObject:self.storeDictionary forKey:@"localstore"];
	[encoder finishEncoding];

    NSString *applicationSupportDirectory = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES)[0];
	NSString *localStorePath = [applicationSupportDirectory stringByAppendingPathComponent:self.fileName];
    NSError* writeError = nil;
	if (![data writeToFile:localStorePath options:NSDataWritingAtomic error:&writeError]) {
        NSLog(@"Could not save local store:%@  error:%@", localStorePath, writeError);
    }
}

- (void)loadLocalStore
{
	//if we've already loaded the dictionary, simply return
    if (self.storeDictionary)
        return;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // Delete old (documents directory) local store if present
	NSString *documentsDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
	NSString *oldLocalStorePath = [documentsDirectory stringByAppendingPathComponent:self.fileName];
    if ([fileManager fileExistsAtPath:oldLocalStorePath]) {
        self->isExistingUser = YES;
        [fileManager removeItemAtPath:oldLocalStorePath error:nil];
    }
    
    NSString *applicationSupportDirectory = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES)[0];
    
    // Create the Application Support directory if it doesn't exist
    if (![fileManager fileExistsAtPath:applicationSupportDirectory])
        [fileManager createDirectoryAtPath:applicationSupportDirectory withIntermediateDirectories:YES attributes:nil error:nil];            
    
    NSString *localStorePath = [applicationSupportDirectory stringByAppendingPathComponent:self.fileName];
	NSData *data = [NSData dataWithContentsOfFile:localStorePath];
	self.storeDictionary = nil;
    if (data) {
		NSKeyedUnarchiver *decoder = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
		self.storeDictionary = [decoder decodeObjectForKey:@"localstore"];
		[decoder finishDecoding];
        self->isExistingUser = YES;
	}

    /* Is the dictionary still nil (from either the data not being loaded or the data being corrupt?
     Then create a new dictionary */
    if (nil == self.storeDictionary) {
        self.storeDictionary = [[NSMutableDictionary alloc] init];
    }
}

- (id)objectForKey:(NSString*)key
{
	return (self.storeDictionary)[key];
}

- (void)setValue:(id)val forKey:(NSString*)key 
{
	[self.storeDictionary setValue:val forKey:key];
}

- (id)initWithUserId:(NSNumber*)userId
{
	if((self = [super init])) {
		self.fileName = [NSString stringWithFormat:@"user_%@.store", userId];
        self->isExistingUser = YES;
	}
	return self;
}

- (void)dealloc
{
	self.storeDictionary = nil;
	self.fileName = nil;
}

- (BOOL)isExistingUser
{
    return self->isExistingUser;
}

#pragma mark - Singleton methods

+ (void)initialize
{
    static BOOL initialized = NO;
    if(!initialized)
    {
        initialized = YES;
        globalInstance = [[LocalStoreHelper alloc] init];
        globalInstance->isExistingUser = NO;
		globalInstance.fileName = GlobalInstanceFileName;
    }
}

+ (LocalStoreHelper*)globalInstance
{
    return globalInstance;
}

- (id)copyWithZone:(NSZone *)zone
{
	if(self == globalInstance) return self;
	else  
	{
		LocalStoreHelper* lsh = [[LocalStoreHelper alloc] init];
		lsh.fileName = self.fileName;
		lsh.storeDictionary = self.storeDictionary;
        lsh->isExistingUser = self->isExistingUser;
		return lsh;
	}
}

@end
