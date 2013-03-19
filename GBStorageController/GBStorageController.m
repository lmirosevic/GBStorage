//
//  GBStorageController.m
//  GBStorageController
//
//  Created by Luka Mirosevic on 29/11/2012.
//  Copyright (c) 2012 Goonbee. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import "GBStorageController.h"

#if TARGET_OS_IPHONE
    #import "GBToolbox.h"
#else
    #import <GBToolbox/GBToolbox.h>
#endif

static NSUInteger const kStorageFileVersion = 1;

@interface GBStorageController ()

@property (strong, nonatomic) NSMutableDictionary *cache;

@end

@implementation GBStorageController

#pragma mark - storage stuff

_singleton(GBStorageController, sharedController);
_lazy(NSMutableDictionary, cache, _cache)

#pragma mark - keyed indexes

-(id)objectForKeyedSubscript:(id)key {
    //make sure key is a string
    if (IsValidString(key)) {
        //if not in cache
        if (!self.cache[key]) {
            //load it
            [self preLoad:key];
        }
        
        //return it
        return self.cache[key];
    }
    else {
        @throw [NSException exceptionWithName:@"GBStorageController error" reason:@"key must be non-empty NSString" userInfo:nil];
        return nil;
    }
}

-(void)setObject:(id<NSCoding>)object forKeyedSubscript:(NSString *)key {
    if (object && IsValidString(key)) {
        //put it in the cache
        self.cache[key] = object;
    }
    else {
        @throw [NSException exceptionWithName:@"GBStorageController error" reason:@"key must be non-empty NSString, and object must also be non-nil" userInfo:nil];
    }
}

#pragma mark - advanced uses

-(void)save {
    //call save for all keys in the cache
    for (NSString *key in self.cache) {
        [self save:key];
    }
}

-(void)save:(NSString *)key {
    if (IsValidString(key)) {
        //make sure object isnt nil, otherwise dont save it
        id object = self.cache[key];
        if (object) {
            //call save util function
            [self _saveObject:object toDiskForKey:key];
        }
    }
    else {
        @throw [NSException exceptionWithName:@"GBStorageController error" reason:@"key must be non-empty NSString, and object must be in cache" userInfo:nil];
    }
}

-(void)preLoad:(NSString *)key {
    if (IsValidString(key)) {
        //load it from disk and save
        id object = [self _readObjectFromDiskForKey:key];
        
        //make sure object isnt nil
        if (object) {
            self.cache[key] = object;
        }
    }
    else {
        @throw [NSException exceptionWithName:@"GBStorageController error" reason:@"key must be non-empty NSString" userInfo:nil];
    }
}

-(void)clearCache {
    //clear entire cache
    self.cache = nil;
}

-(void)clearCacheForKey:(NSString *)key {
    if (IsValidString(key)) {
        //clear that key from cache
        [self.cache removeObjectForKey:key];
    }
    else {
        @throw [NSException exceptionWithName:@"GBStorageController error" reason:@"key must be non-empty NSString" userInfo:nil];
    }
    
}

-(void)deletePermanently:(NSString *)key {
    if (IsValidString(key)) {
        //remove from cache
        [self clearCacheForKey:key];
        
        //remove from disk
        [self _deleteObjectFromDiskForKey:key];
    }
    else {
        @throw [NSException exceptionWithName:@"GBStorageController error" reason:@"key must be non-empty NSString" userInfo:nil];
    }
}

#pragma mark - disk stuff

-(NSString *)_dbSavePathForKey:(NSString *)key {
	//get the path for purchases file
#if TARGET_OS_IPHONE
    NSString *documentsDirectoryPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
#else
    NSString *documentsDirectoryPath = [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:AppBundleIdentifier()];
#endif
    
    //make sure path exists
    @try {
        BOOL isDir;
        if (![[NSFileManager defaultManager] fileExistsAtPath:documentsDirectoryPath isDirectory:&isDir] || !isDir) {
            if (![[NSFileManager defaultManager] createDirectoryAtPath:documentsDirectoryPath withIntermediateDirectories:YES attributes:nil error:nil]) {
                @throw [NSException exceptionWithName:@"GBStorageController" reason:@"file already exists in destination path" userInfo:nil];
            }
        }
    }
    @catch (NSException *exception) {
        @throw [NSException exceptionWithName:@"GBStorageController error" reason:@"could not create directory" userInfo:nil];
    }
    
    //construct path
    NSString *path = [documentsDirectoryPath stringByAppendingPathComponent:[NSString stringWithFormat:@"gb-storage-controller-file-%@-%ld", key, (unsigned long)kStorageFileVersion]];
    
	return path;
}

-(void)_saveObject:(id <NSCoding>)object toDiskForKey:(NSString *)key {
    if (IsValidString(key)) {
        //save to disk
        @try {
            [NSKeyedArchiver archiveRootObject:object toFile:[self _dbSavePathForKey:key]];
        }
        @catch (NSException *exception) {
            @throw [NSException exceptionWithName:@"GBStorageController error" reason:@"something went wrong with archiving db to disk" userInfo:nil];
        }
    }
    else {
        @throw [NSException exceptionWithName:@"GBStorageController error" reason:@"key must be non-empty NSString" userInfo:nil];
    }
}

-(id)_readObjectFromDiskForKey:(NSString *)key {
    id object = nil;
    
    @try {
        if ([[NSFileManager defaultManager] fileExistsAtPath:[self _dbSavePathForKey:key]]) {
            //load database if the file exists
            object = [NSKeyedUnarchiver unarchiveObjectWithFile:[self _dbSavePathForKey:key]];
        }
    }
    @catch (NSException *exception) {
        @throw [NSException exceptionWithName:@"GBStorageController error" reason:@"something went wrong with loading db from disk" userInfo:nil];
    }

    //return object, may be nil
    return object;
}

-(void)_deleteObjectFromDiskForKey:(NSString *)key {
    NSError *error;
    
    @try {
        //check that it exists
        if ([[NSFileManager defaultManager] fileExistsAtPath:[self _dbSavePathForKey:key]]) {
            //delete it
            [[NSFileManager defaultManager] removeItemAtPath:[self _dbSavePathForKey:key] error:&error];
        }
    }
    @catch (NSException *exception) {
        @throw [NSException exceptionWithName:@"GBStorageController error" reason:@"something went wrong with deleting db to disk" userInfo:nil];
    }
}


#pragma mark - mem

-(id)init {
    if (self = [super init]) {
        
    }
    
    return self;
}

-(void)dealloc {
    self.cache = nil;
}

@end