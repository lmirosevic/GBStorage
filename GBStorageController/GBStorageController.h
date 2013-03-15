//
//  GBStorageController.h
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

@interface GBStorageController : NSObject

//Convenience
#define GBStorage ([GBStorageController sharedController])
#define _sc ([GBStorageController sharedController])

//singleton
+(GBStorageController *)sharedController;

//keyed indexing
-(id)objectForKeyedSubscript:(NSString *)key;
-(void)setObject:(id<NSCoding>)object forKeyedSubscript:(NSString *)key;

//save all objects. see below ref rewriting
-(void)save;

//save the object with key key. doesnt do any dirty checking, i.e. rewrites entire object to disk each time
-(void)save:(NSString *)key;

//preload that object into the cache
-(void)preLoad:(NSString *)key;

//clear all objects out of the cache
-(void)clearCache;

//clear cache for a single key
-(void)clearCacheForKey:(NSString *)key;

//delete data for that key from disk and cache
-(void)deletePermanently:(NSString *)key;

@end