# GBStorage ![Version](https://img.shields.io/cocoapods/v/GBStorage.svg?style=flat)&nbsp;![License](https://img.shields.io/badge/license-Apache_2-green.svg?style=flat)

Simple iOS and Mac OS X persistence layer with in-memory caching, optional persistence, pre-loading, namespacing and a sweet syntax.

Usage
------------

Storing:
```objective-c
GBStorageSimple[@"name"] = @"Luka";					// Caches object into memory only
[GBStorageSimple saveAll];							// Persistent in memory objects to disk
```

Reading:
```objective-c
GBStorageSimple[@"name"];							// Returns "Luka", checks the in-memory cache first, then the disk cache. If not found returns nil
```

Specific sync:
```objective-c
[GBStorageSimple save:@"name"];						// Persists a specific object to disk
```

Preloading cache:
```objective-c
[GBStorageSimple preload:@"bigObject"];				// Load an object into memory for fast future access
```

Clear cache:
```objective-c
[GBStorageSimple removeAllFromMemory];				// Evicts entire in-memory cache, but leaves all previosuly peristed files on disk.
[GBStorageSimple removeFromMemory:@"name"];			// Evicts a single key from the in-memory cache. Keep in mind this only releases the strong pointer that GBStorage holds to the object, if your app still holds a strong pointer somewhere then the object will remain in the application memory (however it will be removed from the context of GBStorage).
```

Deleting:
```objective-c
[GBStorageSimple removePermanently:@"bigObject"];	// Removes object from both the in-memory and on-disk cache
```

If you want to use GBStorage as a persistent cache with a max memory usage cap:
```objective-c
GBStorageSimple.maxInMemoryCacheCapacity = 1000000; // set the max in-memory cache capacity to 1MB
[GBStorageSimple setObject:@"someObject" forKey:@"key" withSize:100]; // insert an object into the cache with a known size
```

Don't forget to import header:

```objective-c
#import <GBStorage/GBStorage.h>
```

Namespacing
------------

You can namespace your storage controller, e.g. for different parts of the app, or for use in libraries to avoid conflict.

To use namespacing, use the GBStorage(<namespace>) syntax to return a namespaced instance of GBStorageController. All operations on GBStorage are silo'd to the namespace, e.g. to remove all keys from both memory and on-disk in the `myLibrary` namespace, you would get the correct instance using `GBStorage(NSString *namespace)` and then use `-[GBStorageController removeAllPermanently]`. Example:
```objective-c
[GBStorage(@"myLibrary") removeAllPermanently];
```

Saving and querying works the same way:
```objective-c
GBStorage(@"myLibrary")[@"name"] = @"Luka";
[GBStorage(@"myLibrary") save:@"name"];
```

Namespaces are silo'd
```objective-c
GBStorage(@"namespace1")[@"color"] = @"blue";							// stores the object into in-memory chace of namespace1

GBStorage(@"namespace1")[@"color"];										// returns @"blue"
GBStorage(@"namespace2")[@"color"];										// returns nil

[GBStorage(@"namespace1") saveAll];										// persists all objects in the in-memory cache in namespace1, but does NOT persistent any objects in any other namespaces
```

You can pass `nil` if you don't want to use a namespace, or for backwards data compatibility with GBStorage 1.x.x. There are a few ways to avoid using a namespace, each with identical semantics but slightly different syntax.
```objective-c
GBStorage(nil)[@"someKey"] = @"someObject";								// (1) 2.x.x style syntax
GBStorageSimple[@"someKey"] = @"someObject";							// (2) 1.x.x style syntax. Designed with upgrading from 1.x.x to 2.x.x in mind, can be used in a simple find&replace.
[GBStorageController sharedControllerForNamespace:nil][@"someKey"];		// (3) Actual ObjC method implementation which styles (1) and (2) just call into. It's a little verbose so (1) is it's syntactically sugar'd up version.
```

Performance considerations
------------

Objects *stored* in the in-memory cache are simply retained with a strong pointer. If they could mutate it might be a good idea to pass in a copy to the `GBStorageController`. Once you've stored an object into `GBStorageController`, you CAN mutate the object but you have to keep in mind that the changes won't persist to disk until you call `-[GBStorageController save]`. Objects are not automatically copied for performance reasons.

Keys need to be of type `NSString`. They are automatically copied to avoid undefined behaviour if you were to mutate them.

When using namespaces, if you mutate an object which has been cached in multiple namespaces, all namespaces will see the new value (again because it simply holds a strong pointer to it).

Objects which you pass to `GBStorageController` must conform to the `NSCoding` protocol. Alternatively you can provide your own serialiser and deserialiser if you want, e.g. for images or json.

Naming
------------

The library, Cocoapod and interface all user the name `GBStorage`. The class that actually implements everything (there is just the 1) is called `GBStorageController`.

Dependencies
------------

None.

Change notes
------------

Cocoapod library has been renamed from `GBStorageController` to `GBStorage` for version 2.

Copyright & License
------------

Copyright 2016 Luka Mirosevic

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this work except in compliance with the License. You may obtain a copy of the License in the LICENSE file, or at:

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

