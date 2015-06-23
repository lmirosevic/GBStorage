//
//  GBStorage.m
//  GBStorage
//
//  Created by Luka Mirosevic on 29/11/2012.
//  Copyright (c) 2014 Goonbee. All rights reserved.
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

#import "GBStorage.h"

#import <CommonCrypto/CommonDigest.h>

NSString * const kGBStorageDefaultNamespace =                   nil;// NEVER change this!
NSUInteger const kGBStorageMemoryCapUnlimited =                 0;

static NSUInteger const kStorageFileVersion =                   2;
static NSString * const kDocumentsDirectorySubfolder =          @"GBStorage"; // NEVER change this!
static NSString * const kFilenamePrefix =                       @"gb-storage-controller-file";// NEVER change this!
static NSUInteger const kDefaultStorageMemoryCap =              kGBStorageMemoryCapUnlimited;

@interface GBStorageController ()

@property (copy, atomic, readonly) NSString                     *namespacedStoragePath;
@property (strong, atomic, readonly) NSMutableSet               *potentiallyCachedKeys;
@property (strong, atomic, readonly) NSCache                    *cache;

@end

@implementation GBStorageController

#pragma mark - Memory

-(id)initWithNamespace:(NSString *)storageNamespace {
    if (self = [super init]) {
        // store this in original format so the user can query it later
        _storageNamespace = storageNamespace;
        
        // generate the hashed storage path, or just set it to the const if there is no namespace. There can be no collisions as the kDefaultNameSpaceInstanceName is defined to lie outside of space of potential sha1 digests. This will be used for storing to disk
        _namespacedStoragePath = (storageNamespace == nil) ? nil : [self.class _sha1DigestForString:storageNamespace];

        _cache = [NSCache new];
        _cache.totalCostLimit = kDefaultStorageMemoryCap;
        _potentiallyCachedKeys = [NSMutableSet new];
    }
    
    return self;
}

#pragma mark - API

GBStorageController *GBStorage(NSString *storageNamespace) {
    return [GBStorageController sharedControllerForNamespace:storageNamespace];
}

static NSMutableDictionary *_instances;
+(void)initialize {
    static BOOL initialised = NO;
    if (!initialised) {
        initialised = YES;
        _instances = [NSMutableDictionary new];
    }
}

+(instancetype)sharedControllerForNamespace:(NSString *)storageNamespace {
    static GBStorageController *_defaultInstance;
    @synchronized(self) {
        // verify that the namespace is legal, it can be nil or any non-empty string
        if (!(storageNamespace == nil ||
            ([storageNamespace isKindOfClass:NSString.class] && storageNamespace.length > 0))) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Storage namespace must be either nil for no namespace, or a non-empty string otherwise." userInfo:nil];
        
        // default instance
        if (storageNamespace == nil) {
            if (!_defaultInstance) {
                _defaultInstance = [[self.class alloc] initWithNamespace:storageNamespace];
            }
            
            return _defaultInstance;
        }
        // actual namespaces
        else {
            if (!_instances[storageNamespace]) {
                _instances[storageNamespace] = [[self.class alloc] initWithNamespace:storageNamespace];
            }
            
            return _instances[storageNamespace];
        }
    }
}

-(id)objectForKeyedSubscript:(NSString *)key {
    [self.class _validateKey:key];
    
    // if not in cache...
    if (![self _objectFromCacheForKey:key]) {
        // load it into the cache
        [self preloadIntoMemory:key];
    }
    
    // then return whatever is in the cache now
    return [self _objectFromCacheForKey:key];
}

-(void)setObject:(id<NSCoding>)object forKeyedSubscript:(NSString *)key {
    [self setObject:object forKey:key withSize:0];
}

-(void)setObject:(id<NSCoding>)object forKey:(NSString *)key withSize:(NSUInteger)size {
    [self setObject:object forKey:key withSize:size persistImmediately:NO];
}

-(void)setObject:(id<NSCoding>)object forKey:(NSString *)key withSize:(NSUInteger)size persistImmediately:(BOOL)shouldPersistImmediately {
    [self.class _validateObject:object];
    [self.class _validateKey:key];
    
    // put it in the cache
    [self _addObjectToCache:object forKey:key cost:size];
    
    // potentially save it immediately
    if (shouldPersistImmediately) {
        [self _saveObject:object toDiskForKey:key];
    }
}

-(void)setMaxInMemoryCacheCapacity:(NSUInteger)maxInMemoryCacheCapacity {
    self.cache.totalCostLimit = maxInMemoryCacheCapacity;
}

-(NSUInteger)maxInMemoryCacheCapacity {
    return self.cache.totalCostLimit;
}

-(void)save:(NSString *)key {
    [self.class _validateKey:key];
    
    // get the actual object from the cache
    id object = [self _objectFromCacheForKey:key];
    
    // make sure the key corresponds to an object that's actually in the cache
    if (object) {
        // save it to disk
        [self _saveObject:object toDiskForKey:key];
    }
}

-(void)saveAll {
    // call save for all keys in the cache
    NSMutableArray *evictedKeys = [NSMutableArray new];
    for (NSString *key in [self.potentiallyCachedKeys copy]) {
        // save the object if it's in the cache
        if ([self _objectFromCacheForKey:key]) {
            [self save:key];
        }
        // otherwise mark it for cleanup from our internal keys bookkeeping list because it's been evicted
        else {
            [evictedKeys addObject:key];
        }
    }
    
    // clean up internal bookkeeping
    for (NSString *key in evictedKeys) {
        [self.potentiallyCachedKeys removeObject:key];
    }
}

-(void)preloadIntoMemory:(NSString *)key {
    [self.class _validateKey:key];
    
    // only do it if it's not already loaded into memory
    if (![self _objectFromCacheForKey:key]) {
        // load it from disk
        id object = [self _readObjectFromDiskForKey:key];
        
        // make sure an object on disk matches the key
        if (object) {
            // get its size
            NSUInteger size = [self _sizeForObjectOnDiskForKey:key];
            
            // add it into the cache
            [self _addObjectToCache:object forKey:key cost:size];
        }
    }
}

-(void)removeFromMemory:(NSString *)key {
    [self.class _validateKey:key];
    
    [self _removeObjectFromCache:key];
}

-(void)removeAllFromMemory {
    [self _removeAllObjectsFromCache];
}

-(void)removePermanently:(NSString *)key {
    [self.class _validateKey:key];
    
    // remove the object from the cache
    [self _removeObjectFromCache:key];
    
    // remove it from disk
    [self _deleteObjectFromDiskForKey:key];
}

-(void)removeAllPermanently {
    // clean in memory cache
    [self _removeAllObjectsFromCache];
    
    // clear disk cache
    [self _clearCacheFolder];
}

#pragma mark - Util

+(NSString *)_sha1DigestForString:(NSString *)string {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    
    return output;
}

+(void)_validateKey:(NSString *)key {
    if (!key || key.length == 0) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"GBStorageController: key must be non-empty NSString" userInfo:nil];
}

+(void)_validateObject:(id)object {
    if (!object || ![object conformsToProtocol:@protocol(NSCoding)]) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"GBStorageController: object must not be nil and must conform to NSCoding protocol" userInfo:nil];
}

#pragma mark - Util:Cache

-(void)_removeAllObjectsFromCache {
    @synchronized(self) {
        [self.cache removeAllObjects];
        [self.potentiallyCachedKeys removeAllObjects];
    }
}

-(void)_removeObjectFromCache:(NSString *)key {
    @synchronized(self) {
        [self.cache removeObjectForKey:key];
        [self.potentiallyCachedKeys removeObject:key];
    }
}

-(void)_addObjectToCache:(id)object forKey:(NSString *)key cost:(NSUInteger)cost {
    @synchronized(self) {
        [self.cache setObject:object forKey:key cost:cost];
        [self.potentiallyCachedKeys addObject:key];
    }
}

-(id)_objectFromCacheForKey:(NSString *)key {
    @synchronized(self) {
        return [self.cache objectForKey:key];
    }
}

#pragma mark - Util:Storage

-(void)_ensureFileIsLatestVersionForKey:(NSString *)key {
    // we're using namespaces, which is a feature of GBStorage 2.x.x
    if (self.namespacedStoragePath != nil) {
        //noop
    }
    // not using namespaces, might have to migrate files
    else {
        [self _upgradeFileForKeyFrom1to2:key];
    }
}

-(void)_upgradeFileForKeyFrom1to2:(NSString *)key {
    // 1 -> 2 changes:
    //   - added hashing to the keys when storing, so that path affecting characters like "/" don't mess with the internals

    @synchronized(self) {
        // check if it exists under version 1
        BOOL isDir;
        if ([[NSFileManager defaultManager] fileExistsAtPath:[self _diskSavePathForKey:key version:1] isDirectory:&isDir] && !isDir) {
            // just rename the file so it conforms to version 2
            if (![[NSFileManager defaultManager] moveItemAtPath:[self _diskSavePathForKey:key version:1] toPath:[self _diskSavePathForKey:key version:2] error:nil]) {
                @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Failed to migrate file from version 1 to 2" userInfo:nil];
            }
        }
    }
}

-(void)_clearCacheFolder {
    @synchronized(self) {
        NSString *cacheDirectoryPath = [self _diskCacheDirectory];
        for (NSString *fileName in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cacheDirectoryPath error:nil]) {

            NSString *filePath = [cacheDirectoryPath stringByAppendingPathComponent:fileName];
            
            BOOL isDir;
            if ([[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDir] || !isDir) {
                // only remove it if it's a GBStorage file, which can be determined by the prefix
                if ([fileName hasPrefix:kFilenamePrefix]) {
                    if (![[NSFileManager defaultManager] removeItemAtPath:filePath error:nil]) {
                        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Failed to delete file in cache directory" userInfo:nil];
                    }
                }
            }
        }
    }
}

-(NSString *)_documentsDirectoryPath {
    #if TARGET_OS_IPHONE
        return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    #else
        return [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:[[NSBundle mainBundle] infoDictionary][@"CFBundleIdentifier"]];
    #endif
}

-(NSString *)_diskCacheDirectory {
    NSString *documentsDirectoryPath = [self _documentsDirectoryPath];
    
    // if we have a namespace, then use it
    NSString *diskCacheDirectory;
    if (self.namespacedStoragePath == kGBStorageDefaultNamespace) {
        diskCacheDirectory = documentsDirectoryPath;
    }
    else {
        diskCacheDirectory = [[documentsDirectoryPath stringByAppendingPathComponent:kDocumentsDirectorySubfolder] stringByAppendingPathComponent:self.namespacedStoragePath];
    }
    
    @synchronized(self) {
        // make sure path exists
        BOOL isDir;
        if (![[NSFileManager defaultManager] fileExistsAtPath:diskCacheDirectory isDirectory:&isDir] || !isDir) {
            // directory doesn't exist, so create it
            if (![[NSFileManager defaultManager] createDirectoryAtPath:diskCacheDirectory withIntermediateDirectories:YES attributes:nil error:nil]) {
                @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Failed to create storage directory" userInfo:nil];
            }
        }
    }
    
    return diskCacheDirectory;
}

-(NSString *)_diskSavePathForKey:(NSString *)key {
    return [self _diskSavePathForKey:key version:kStorageFileVersion];
}

-(NSString *)_diskSavePathForKey:(NSString *)key version:(NSUInteger)version {
    //construct path
    switch (version) {
        case 1: {
            // version 1 files were stored plainly in the directory
            NSString *directory = [self _documentsDirectoryPath];
            return [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@-%ld", kFilenamePrefix, key, (unsigned long)1]];
        } break;
            
        case 2: {
            // version 2 files are stored plainly in the directory when not using a namespace, and in some subfolder when using a namespace. _diskCacheDirectory handles this
            NSString *directory = [self _diskCacheDirectory];
            NSString *d = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@-%ld", kFilenamePrefix, [self.class _sha1DigestForString:key], (unsigned long)2]];
            return d;
        } break;
            
        default: {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"Unimplemented storage version: %ld", (unsigned long)version] userInfo:nil];
        } break;
    }
}

-(void)_saveObject:(id <NSCoding>)object toDiskForKey:(NSString *)key {
    // migrate file if needed
    [self _ensureFileIsLatestVersionForKey:key];
    
    // save to disk
    @synchronized(self) {
        [NSKeyedArchiver archiveRootObject:object toFile:[self _diskSavePathForKey:key]];
    }
}

-(id)_readObjectFromDiskForKey:(NSString *)key {
    // migrate file if needed
    [self _ensureFileIsLatestVersionForKey:key];
    
    @synchronized(self) {
        // check if the file exists
        if ([[NSFileManager defaultManager] fileExistsAtPath:[self _diskSavePathForKey:key]]) {
            // load it
            return [NSKeyedUnarchiver unarchiveObjectWithFile:[self _diskSavePathForKey:key]];
        }
        else {
            return nil;
        }
    }
}

-(NSUInteger)_sizeForObjectOnDiskForKey:(NSString *)key {
    @synchronized(self) {
        return (NSUInteger)[[[NSFileManager defaultManager] attributesOfItemAtPath:[self _diskSavePathForKey:key] error:nil] fileSize];
    }
}

-(void)_deleteObjectFromDiskForKey:(NSString *)key {
    // migrate file if needed
    [self _ensureFileIsLatestVersionForKey:key];
    
    @synchronized(self) {
        // check if the file exists
        if ([[NSFileManager defaultManager] fileExistsAtPath:[self _diskSavePathForKey:key]]) {
            // delete it
            [[NSFileManager defaultManager] removeItemAtPath:[self _diskSavePathForKey:key] error:nil];
        }
    }
}

@end
