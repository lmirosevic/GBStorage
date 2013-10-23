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

static NSUInteger const kGBStorageFileVersion = 2;

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
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"GBStorageController: key must be non-empty NSString" userInfo:nil];
    }
}

-(void)setObject:(id<NSCoding>)object forKeyedSubscript:(NSString *)key {
    if (!object) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"kobject must also be non-nil" userInfo:nil];
    if (!IsValidString(key)) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"key must be non-empty NSString" userInfo:nil];
    
    //put it in the cache
    self.cache[key] = object;
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
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"GBStorageController: key must be non-empty NSString, and object must be in cache" userInfo:nil];
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
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"GBStorageController: key must be non-empty NSString" userInfo:nil];
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
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"GBStorageController: key must be non-empty NSString" userInfo:nil];
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
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"GBStorageController: key must be non-empty NSString" userInfo:nil];
    }
}

#pragma mark - storage upgrading

-(void)_ensureFileIsLatestVersionForKey:(NSString *)key {
    [self _upgradeFileForKeyFrom1to2:key];
}

-(void)_upgradeFileForKeyFrom1to2:(NSString *)key {
    //check if it exists under version 1
    BOOL isDir;
    if ([[NSFileManager defaultManager] fileExistsAtPath:[self _dbSavePathForKey:key version:1] isDirectory:&isDir] && !isDir) {
        //rename it to version 2
        NSError *error;
        [[NSFileManager defaultManager] moveItemAtPath:[self _dbSavePathForKey:key version:1] toPath:[self _dbSavePathForKey:key version:2] error:&error];
    }
}

#pragma mark - disk stuff

-(NSString *)_dbSaveDirectory {
    //get the path for purchases file
#if TARGET_OS_IPHONE
    NSString *documentsDirectoryPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
#else
    NSString *documentsDirectoryPath = [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:AppBundleIdentifier()];
#endif
    
    //make sure path exists
    BOOL isDir;
    if (![[NSFileManager defaultManager] fileExistsAtPath:documentsDirectoryPath isDirectory:&isDir] || !isDir) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:documentsDirectoryPath withIntermediateDirectories:YES attributes:nil error:nil]) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"GBStorageController: file already exists in destination path" userInfo:nil];
        }
    }
    
    return documentsDirectoryPath;
}

//convenience that just returns it for the latest version
-(NSString *)_dbSavePathForKey:(NSString *)key {
    return [self _dbSavePathForKey:key version:kGBStorageFileVersion];
}

-(NSString *)_dbSavePathForKey:(NSString *)key version:(NSUInteger)version {
    NSString *documentsDirectoryPath = [self _dbSaveDirectory];
    
    //construct path
    switch (version) {
        case 1: {
            return [documentsDirectoryPath stringByAppendingPathComponent:[NSString stringWithFormat:@"gb-storage-controller-file-%@-%ld", key, (unsigned long)1]];
        } break;
            
        case 2: {
            return [documentsDirectoryPath stringByAppendingPathComponent:[NSString stringWithFormat:@"gb-storage-controller-file-%@-%ld", key.sha1, (unsigned long)2]];
        } break;
            
        default: {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Tried to get save path for unkown file version" userInfo:@{@"fileVersion": @(version)}];
        } break;
    }
}

-(void)_saveObject:(id <NSCoding>)object toDiskForKey:(NSString *)key {
    //migrate file if needed
    [self _ensureFileIsLatestVersionForKey:key];
    
    //save to disk
    [NSKeyedArchiver archiveRootObject:object toFile:[self _dbSavePathForKey:key]];
}

-(id)_readObjectFromDiskForKey:(NSString *)key {
    //migrate file if needed
    [self _ensureFileIsLatestVersionForKey:key];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[self _dbSavePathForKey:key]]) {
        //load database if the file exists
        return [NSKeyedUnarchiver unarchiveObjectWithFile:[self _dbSavePathForKey:key]];
    }
    else {
        return nil;
    }
}

-(void)_deleteObjectFromDiskForKey:(NSString *)key {
    //migrate file if needed
    [self _ensureFileIsLatestVersionForKey:key];
    
    //check that it exists
    if ([[NSFileManager defaultManager] fileExistsAtPath:[self _dbSavePathForKey:key]]) {
        //delete it
        NSError *error;
        [[NSFileManager defaultManager] removeItemAtPath:[self _dbSavePathForKey:key] error:&error];
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