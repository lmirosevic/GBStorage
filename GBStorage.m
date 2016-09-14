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

NSString * const kGBStorageDefaultNamespace =                       nil;// NEVER change this!
NSUInteger const kGBStorageMemoryCapUnlimited =                     0;

GBStorageSerialiser const kGBStorageNSCodingSerialiser = ^NSData *(id object) {
    return [NSKeyedArchiver archivedDataWithRootObject:object];
};

GBStorageDeserialiser const kGBStorageNSCodingDeserialiser = ^id(NSData *data) {
    return [NSKeyedUnarchiver unarchiveObjectWithData:data];
};

static NSUInteger const kStorageFileVersion =                       2;
static NSString * const kDocumentsDirectorySubfolder =              @"GBStorage"; // NEVER change this!
static NSString * const kFilenamePrefix =                           @"gb-storage-controller-file";// NEVER change this!
static NSUInteger const kDefaultStorageMemoryCap =                  kGBStorageMemoryCapUnlimited;

@interface GBStorageController () <NSCacheDelegate>

@property (copy, atomic, readonly) NSString                         *namespacedStoragePath;
@property (strong, atomic, readonly) NSMutableSet<NSString *>       *cachedKeysMutable;
@property (strong, atomic, readonly) NSCache<NSString*, id>         *cache;

@property (strong, atomic, readonly) NSMapTable<id, NSString *>     *objectToKeyAssociationsTable;

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
        _cache.delegate = self;
        _cachedKeysMutable = [NSMutableSet new];
        
        // default serialisers
        self.serialiser = kGBStorageNSCodingSerialiser;
        self.deserialiser = kGBStorageNSCodingDeserialiser;
        
        _objectToKeyAssociationsTable = [NSMapTable mapTableWithKeyOptions:(NSPointerFunctionsObjectPointerPersonality | NSPointerFunctionsWeakMemory) valueOptions:NSPointerFunctionsCopyIn];
    }
    
    return self;
}

#pragma mark - API

GBStorageController *GBStorage(NSString *storageNamespace) {
    return [GBStorageController sharedControllerForNamespace:storageNamespace];
}

static NSMutableDictionary *_instances;
+ (void)initialize {
    static BOOL initialised = NO;
    if (!initialised) {
        initialised = YES;
        _instances = [NSMutableDictionary new];
    }
}

+ (instancetype)sharedControllerForNamespace:(NSString *)storageNamespace {
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

- (id)objectForKeyedSubscript:(NSString *)key {
    [self.class _validateKey:key];
    
    // attempt to fetch from cache first
    id object = [self _objectFromCacheForKey:key];
    
    // if not in cache
    if (!object) {
        // load it, and also store it into the cache
        object = [self _loadFromDiskAndAddToCache:key];
    }
    
    // return the object
    return object;
}

- (void)setObject:(id)object forKeyedSubscript:(NSString *)key {
    [self setObject:object forKey:key withSize:0];
}

- (void)setObject:(id)object forKey:(NSString *)key withSize:(NSUInteger)size {
    [self setObject:object forKey:key withSize:size persistImmediately:NO];
}

- (void)setObject:(id)object forKey:(NSString *)key withSize:(NSUInteger)size persistImmediately:(BOOL)shouldPersistImmediately {
    [self.class _validateObject:object];
    [self.class _validateKey:key];
    
    // put it in the cache
    [self _addObjectToCache:object forKey:key cost:size];
    
    // potentially save it immediately
    if (shouldPersistImmediately) {
        [self _saveObject:object toDiskForKey:key];
    }
}

- (void)setMaxInMemoryCacheCapacity:(NSUInteger)maxInMemoryCacheCapacity {
    self.cache.totalCostLimit = maxInMemoryCacheCapacity;
}

- (NSUInteger)maxInMemoryCacheCapacity {
    return self.cache.totalCostLimit;
}

- (BOOL)isCached:(nonnull NSString *)key {
    [self.class _validateKey:key];
    
    return [self.cachedKeysMutable containsObject:key];
}

- (NSSet<NSString *> *)cachedKeys {
    return [self.cachedKeysMutable copy];
}

- (void)save:(NSString *)key {
    [self.class _validateKey:key];
    
    // get the actual object from the cache
    id object = [self _objectFromCacheForKey:key];
    
    // make sure the key corresponds to an object that's actually in the cache
    if (object) {
        // save it to disk
        [self _saveObject:object toDiskForKey:key];
    }
}

- (void)saveAll {
    // call save for all keys in the cache
    for (NSString *key in self.cachedKeysMutable) {
        [self save:key];
    }
}

- (void)preloadIntoMemory:(NSString *)key {
    [self.class _validateKey:key];
    
    [self _loadFromDiskAndAddToCache:key];
}

- (void)removeFromMemory:(NSString *)key {
    [self.class _validateKey:key];
    
    [self _removeObjectFromCache:key];
}

- (void)removeAllFromMemory {
    [self _removeAllObjectsFromCache];
}

- (void)removePermanently:(NSString *)key {
    [self.class _validateKey:key];
    
    // remove the object from the cache
    [self _removeObjectFromCache:key];
    
    // remove it from disk
    [self _deleteObjectFromDiskForKey:key];
}

- (void)removeAllPermanently {
    // clean in memory cache
    [self _removeAllObjectsFromCache];
    
    // clear disk cache
    [self _clearCacheFolder];
}

#pragma mark - Util

+ (NSString *)_sha1DigestForString:(NSString *)string {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    
    return output;
}

+ (void)_validateKey:(NSString *)key {
    if (!key || key.length == 0) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"GBStorageController: key must be non-empty NSString" userInfo:nil];
}

+ (void)_validateObject:(id)object {
    if (!object) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"GBStorageController: object must not be nil and must conform to NSCoding protocol" userInfo:nil];
}

#pragma mark - Util:Cache

- (void)_removeAllObjectsFromCache {
    @synchronized(self) {
        [self.cache removeAllObjects];
        [self.cachedKeysMutable removeAllObjects];
    }
}

- (void)_removeObjectFromCache:(NSString *)key {
    @synchronized(self) {
        [self.cache removeObjectForKey:key];
        [self.cachedKeysMutable removeObject:key];
    }
}

- (void)_addObjectToCache:(id)object forKey:(NSString *)key cost:(NSUInteger)cost {
    @synchronized(self) {
        [self.objectToKeyAssociationsTable setObject:key forKey:object];
        [self.cache setObject:object forKey:key cost:cost];
        [self.cachedKeysMutable addObject:key];
    }
}

- (id)_objectFromCacheForKey:(NSString *)key {
    @synchronized(self) {
        return [self.cache objectForKey:key];
    }
}

#pragma mark - Util:Marshalling

- (NSData *)_serialisedDataForObject:(id)object {
    return self.serialiser(object);
}

- (id)_objectForSerialisedData:(NSData *)data {
    return self.deserialiser(data);
}

#pragma mark - Util:Storage

- (void)_ensureFileIsLatestVersionForKey:(NSString *)key {
    // we're using namespaces, which is a feature of GBStorage 2.x.x
    if (self.namespacedStoragePath != nil) {
        //noop
    }
    // not using namespaces, might have to migrate files
    else {
        [self _upgradeFileForKeyFrom1to2:key];
    }
}

- (void)_upgradeFileForKeyFrom1to2:(NSString *)key {
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

- (void)_clearCacheFolder {
    @synchronized(self) {
        // cleanup disk cache and temporary directory paths
        for (NSString *path in @[[self _diskCacheDirectory], [self _temporaryDirectory]]) {
            for (NSString *fileName in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil]) {
                NSString *filePath = [path stringByAppendingPathComponent:fileName];
                
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
}

- (NSString *)_documentsDirectoryPath {
    #if TARGET_OS_IPHONE
        return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    #else
        return [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:[[NSBundle mainBundle] infoDictionary][@"CFBundleIdentifier"]];
    #endif
}

- (NSString *)_diskCacheDirectory {
    return [self _namespaceDirectorPathFromPath:[self _documentsDirectoryPath]];
}

- (NSString *)_temporaryDirectory {
    return [self _namespaceDirectorPathFromPath:NSTemporaryDirectory()];
}

- (NSString *)_namespaceDirectorPathFromPath:(NSString *)path {
    // if we have a namespace, then use it
    NSString *namespaceDirectorPath;
    if (self.namespacedStoragePath == kGBStorageDefaultNamespace) {
        namespaceDirectorPath = path;
    }
    else {
        namespaceDirectorPath = [[path stringByAppendingPathComponent:kDocumentsDirectorySubfolder] stringByAppendingPathComponent:self.namespacedStoragePath];
    }
    
    @synchronized(self) {
        // make sure path exists
        BOOL isDir;
        if (![[NSFileManager defaultManager] fileExistsAtPath:namespaceDirectorPath isDirectory:&isDir] || !isDir) {
            // directory doesn't exist, so create it
            if (![[NSFileManager defaultManager] createDirectoryAtPath:namespaceDirectorPath withIntermediateDirectories:YES attributes:nil error:nil]) {
                @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Failed to create storage directory" userInfo:nil];
            }
        }
    }
    
    return namespaceDirectorPath;
}

- (NSString *)_diskSavePathForKey:(NSString *)key {
    return [self _diskSavePathForKey:key version:kStorageFileVersion];
}

- (NSString *)_temporarySavePathForKey:(NSString *)key {
    return [[self _temporaryDirectory] stringByAppendingPathComponent:[self _diskSaveFilenameForKey:key version:kStorageFileVersion]];
}

- (NSString *)_diskSaveFilenameForKey:(NSString *)key version:(NSUInteger)version {
    //construct filename
    switch (version) {
        case 1: {
            return [NSString stringWithFormat:@"%@-%@-%ld", kFilenamePrefix, key, (unsigned long)1];
        } break;
        
        case 2: {
            return [NSString stringWithFormat:@"%@-%@-%ld", kFilenamePrefix, [self.class _sha1DigestForString:key], (unsigned long)2];
        } break;
        
        default: {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"Unimplemented storage version: %ld", (unsigned long)version] userInfo:nil];
        } break;
    }
}

- (NSString *)_diskSavePathForKey:(NSString *)key version:(NSUInteger)version {
    NSString *directory;
    
    //construct path
    switch (version) {
        case 1: {
            // version 1 files were stored plainly in the directory
            directory = [self _documentsDirectoryPath];
        } break;
        
        case 2: {
            // version 2 files are stored plainly in the directory when not using a namespace, and in some subfolder when using a namespace. _diskCacheDirectory handles this
            directory = [self _diskCacheDirectory];
        } break;
        
        default: {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"Unimplemented storage version: %ld", (unsigned long)version] userInfo:nil];
        } break;
    }
    
    return [directory stringByAppendingPathComponent:[self _diskSaveFilenameForKey:key version:version]];
}

- (void)_saveObject:(id)object toDiskForKey:(NSString *)key {
    // migrate file if needed
    [self _ensureFileIsLatestVersionForKey:key];
    
    NSString *tempPath = [self _temporarySavePathForKey:key];
    NSString *savePath = [self _diskSavePathForKey:key];

    @synchronized(self) {
        // first serialise the data
        NSData *serialisedData = [self _serialisedDataForObject:object];
        
        // two phase save strategy. First archive to temporary file and then move temporary file to desired save location
        if ([serialisedData writeToFile:tempPath atomically:YES]) {
            [[NSFileManager defaultManager] replaceItemAtURL:[NSURL fileURLWithPath:savePath] withItemAtURL:[NSURL fileURLWithPath:tempPath] backupItemName:nil options:0 resultingItemURL:nil error:nil];
        }
    }
}

- (id)_readObjectFromDiskForKey:(NSString *)key {
    // migrate file if needed
    [self _ensureFileIsLatestVersionForKey:key];
    
    // helper block which returns unarcived object from file if file exists and suppresses NSKeyedUnarchiver exceptions if file is currupred in Release
    id(^readObjectBlock)(NSString *) = ^id(NSString *path) {
        @synchronized(self) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
#ifdef DEBUG
                
                NSData *fileData = [NSData dataWithContentsOfFile:path];
                return [self _objectForSerialisedData:fileData];
#else
                @try {
                    NSData *fileData = [NSData dataWithContentsOfFile:path];
                    return [self _objectForSerialisedData:fileData];
                }
                @catch (NSException *exception) {
                    return nil;
                }
#endif
            }
            else {
                return nil;
            }
        }
    };
    
    NSString *tempPath = [self _temporarySavePathForKey:key];
    NSString *savePath = [self _diskSavePathForKey:key];
    
    //  temp object is always the latest, try to unarchive temp object first
    id savedObject = readObjectBlock(tempPath);
    if (savedObject) {
        // move it back to Documents
        @synchronized(self) {
            [[NSFileManager defaultManager] replaceItemAtURL:[NSURL fileURLWithPath:savePath] withItemAtURL:[NSURL fileURLWithPath:tempPath] backupItemName:nil options:0 resultingItemURL:nil error:nil];
        }
    } else {
        // if failed then the latest object is in documents try to unarchive object
        savedObject = readObjectBlock(savePath);
    }
    return savedObject;
}

- (NSUInteger)_sizeForObjectOnDiskForKey:(NSString *)key {
    @synchronized(self) {
        return (NSUInteger)[[[NSFileManager defaultManager] attributesOfItemAtPath:[self _diskSavePathForKey:key] error:nil] fileSize];
    }
}

- (void)_deleteObjectFromDiskForKey:(NSString *)key {
    // migrate file if needed
    [self _ensureFileIsLatestVersionForKey:key];
    
    @synchronized(self) {
        // cleanup disk cache and temporary file paths
        for (NSString *path in @[[self _diskSavePathForKey:key], [self _temporarySavePathForKey:key]]) {
            // check if the file exists
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                // delete it
                [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            }
        }
    }
}

- (id)_loadFromDiskAndAddToCache:(NSString *)key {
    // attempt to load it from cache first
    id object = [self _objectFromCacheForKey:key];
    
    // if we don't have it...
    if (!object) {
        // load it from disk
        object = [self _readObjectFromDiskForKey:key];
        
        // cache it if it exists
        if (object) [self _addObjectToCache:object forKey:key cost:[self _sizeForObjectOnDiskForKey:key]];
    }
    
    // return the object--which is strongly retained here--immediately
    return object;
}

#pragma mark - Eviction

- (void)cache:(NSCache *)cache willEvictObject:(id)obj {
    // remove this key from the potentially cached keys
    NSString *key = [self.objectToKeyAssociationsTable objectForKey:obj];
    [self.cachedKeysMutable removeObject:key];
    
    // we jump to the main thread, firstly to guarantee that we are calling this on the main thread, and secondly to ensure that the code is executed outside of this frame as performing changes to the cache at this time is not supported by NSCache
    dispatch_async(dispatch_get_main_queue(), ^{
        // notify our delegate that the object has been evicted
        if ([self.delegate respondsToSelector:@selector(storage:didEvictObject:forKey:)]) {
            [self.delegate storage:self didEvictObject:obj forKey:key];
        }
    });
}

@end
