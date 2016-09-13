//
//  GBStorage.h
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

FOUNDATION_EXTERN NSString * _Nonnull const kGBStorageDefaultNamespace;
FOUNDATION_EXTERN NSUInteger const kGBStorageMemoryCapUnlimited;

typedef NSData * _Nullable(^GBStorageSerialiser)(id _Nonnull object);
typedef id _Nullable(^GBStorageDeserialiser)(NSData * _Nonnull data);

FOUNDATION_EXTERN GBStorageSerialiser _Nonnull const kGBStorageNSCodingSerialiser;
FOUNDATION_EXTERN GBStorageDeserialiser _Nonnull const kGBStorageNSCodingDeserialiser;

@protocol GBStorageDelegate;

@interface GBStorageController : NSObject

/**
 Shorthand for GBStorage(nil), i.e. to use GBStorage with no namespace.
 
 This is a semantically equivalent replacement for the GBStorage macro from 1.x.x
 */
#define GBStorageSimple (GBStorage(nil))

/**
 Shorthand for `+[GBStorageController sharedControllerForNamespace:]` so callers can use the parens syntax, e.g. `GBStorage(@"some.namespace")[@"myObject"]`.
 
 Pass kGBStorageDefaultNamespace or nil if you don't want to use a namespace, or for backwards compatibility with GBStorage 1.x.x
 */
GBStorageController * _Nonnull GBStorage(NSString * _Nonnull storageNamespace);

/**
 Returns a namespaced singleton instance of GBStorageController. The same resource key can refer to different resources across different namespaces. Aggregate operations like saveAll and removeAllPermanently do not cross namespace boundaries.
 
  Pass kGBStorageDefaultNamespace or nil if you don't want to use a namespace, or for backwards compatibility with GBStorage 1.x.x
 */
+ (nonnull instancetype)sharedControllerForNamespace:(nullable NSString *)storageNamespace;

/**
 The delegate object for this GBStorage instance.
 */
@property (weak, nonatomic, nullable) id<GBStorageDelegate> delegate;

/**
 Fetches an object from the cache. Tries memory first, then disk. If no object found for the key, returns nil.
 */
- (nullable id)objectForKeyedSubscript:(nonnull NSString *)key;

/**
 Stores an object into the in memory cache. To persist the object to disk so it's available on subsequent app launches, call `-[GBStorageController save:]`.
 */
- (void)setObject:(nonnull id)object forKeyedSubscript:(nonnull NSString *)key;

/**
 Stores an object into the in memory cache, with a cost associated with it. It will evict objects according LRU-style once the memory capacity is exceeded.
 */
- (void)setObject:(nonnull id)object forKey:(nonnull NSString *)key withSize:(NSUInteger)size;
/**
 Stores an object into the in memory cache, with a cost associated with it. It will evict objects according LRU-style once the memory capacity is exceeded. If `shouldPersistImmediately` is set to YES, then the object is immediately saved. Use this for cases where you have set a memory cap but want to guarantee that objects will remain cached on disk.
 */
- (void)setObject:(nonnull id)object forKey:(nonnull NSString *)key withSize:(NSUInteger)size persistImmediately:(BOOL)shouldPersistImmediately;

/**
 Lets you set a memory cap for how much the in-memory cache is allowed to use. In terms of cost, as defined by the cost parameter sent to `-[GBStorageController setObject:forKey:withCost:]`
 */
@property (assign, nonatomic) NSUInteger maxInMemoryCacheCapacity; // default: kGBStorageMemoryCapUnlimited

/**
 The serialiser for this namespace. Defaults to NSCoding.
 */
@property (copy, atomic, nonnull) GBStorageSerialiser serialiser;

/**
 The deserialiser for this namespace. Defaults to NSCoding.
 */
@property (copy, atomic, nonnull) GBStorageDeserialiser deserialiser;

/**
 Returns YES if the object for `key` is in the in-memory cache.
 
 Objects can be removed from the cache at any time, so it is possible that calling `objectForKeyedSubscript:` immediately following a call to `isCached` will cause a cache miss.
 */
- (BOOL)isCached:(nonnull NSString *)key;

/**
 The set of keys for the objects which are still in the cache.
 
 Objects can be removed from the cache at any time, so it is possible that calling `objectForKeyedSubscript:` immediately following a call to `cachedKeys` on one of its keys will cause a cache miss.
 */
@property (copy, nonatomic, nonnull) NSSet<NSString *> *cachedKeys;

/**
 Save the resource to disk. Doesn't do any dirty checking, i.e. rewrites the entire object to disk each time.
 */
- (void)save:(nonnull NSString *)key;

/**
 Save all resources to disk. Doesn't do any dirty checking, i.e. rewrites the entire object to disk each time.
 */
- (void)saveAll;

/**
 Preloads that resource into memory, if it isn't already there. 
 */
- (void)preloadIntoMemory:(nonnull NSString *)key;

/**
 Removes a particular resource from the in-memory cache.
 */
- (void)removeFromMemory:(nonnull NSString *)key;

/**
 Removes all resources stored in the in-memory cache.
 */
- (void)removeAllFromMemory;

/**
 Deletes the resource for the key.
 */
- (void)removePermanently:(nonnull NSString *)key;

/**
 Deletes all the data stored on disk and from memory.
 */
- (void)removeAllPermanently;

/**
 Returns the namespace of this storage controller
 */
@property (strong, nonatomic, readonly, nullable) NSString *storageNamespace;

@end

@protocol GBStorageDelegate <NSObject>
@optional

/**
 Called when the GBStorage instance has evicted an object from the cache.
 
 Whether or not the object is still cached inside the implementation of this method is undefined. Generally one should assume that the object has been evicted, or if not will be very soon.
 */
- (void)storage:(nonnull GBStorageController *)storageController didEvictObject:(nonnull id)object forKey:(nonnull NSString *)key;

@end
