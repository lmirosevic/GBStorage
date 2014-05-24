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

extern NSString * const kGBStorageDefaultNamespace;

@interface GBStorageController : NSObject

/**
 Shorthand for GBStorage(nil), i.e. to use GBStorage with no namespace.
 
 This is a semantically equivalent replacement for the GBStorage macro from 1.x.x
 */
#define GBStorageSimple (GBStorage(nil))

/**
 Shorthand for +[GBStorageController sharedControllerForNamespace:] so callers can use the parens syntax, e.g. `GBStorage(@"some.namespace")[@"myObject"]`.
 
 Pass kGBStorageDefaultNamespace or nil if you don't want to use a namespace, or for backwards compatibility with GBStorage 1.x.x
 */
GBStorageController *GBStorage(NSString *storageNamespace);

/**
 Returns a namespaced singleton instance of GBStorageController. The same resource key can refer to different resources across different namespaces. Aggregate operations like saveAll and removeAllPermanently do not cross namespace boundaries.
 
  Pass kGBStorageDefaultNamespace or nil if you don't want to use a namespace, or for backwards compatibility with GBStorage 1.x.x
 */
+(instancetype)sharedControllerForNamespace:(NSString *)storageNamespace;

/**
 Fetches an object from the cache. Tries memory first, then disk. If no object found for the key, returns nil.
 */
-(id)objectForKeyedSubscript:(NSString *)key;

/**
 Stores an object into the in memory cache. To persist the object to disk so it's available on subsequent app launches, call -[GBStorageController save:].
 */
-(void)setObject:(id<NSCoding>)object forKeyedSubscript:(NSString *)key;

/**
 Save the resource to disk. Doesn't do any dirty checking, i.e. rewrites the entire object to disk each time.
 */
-(void)save:(NSString *)key;

/**
 Save all resources to disk. Doesn't do any dirty checking, i.e. rewrites the entire object to disk each time.
 */
-(void)saveAll;

/**
 Preloads that resource into memory, if it isn't already there.
 */
-(void)preloadIntoMemory:(NSString *)key;

/**
 Removes a particular resource from the in-memory cache.
 */
-(void)removeFromMemory:(NSString *)key;

/**
 Removes all resources stored in the in-memory cache.
 */
-(void)removeAllFromMemory;

/**
 Deletes the resource for the key.
 */
-(void)removePermanently:(NSString *)key;

/**
 Deletes all the data stored on disk and from memory.
 */
-(void)removeAllPermanently;

/**
 Returns the namespace of this storage controller
 */
@property (strong, nonatomic, readonly) NSString *storageNamespace;

@end
