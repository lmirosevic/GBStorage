GBStorageController
============

Simple iOS persistence layer with in memory caching

Usage
------------

First import header:

```objective-c
#import "GBStorageController.h"
```

Storing:

```objective-c
GBStorageController[@"name"] = @"Luka";		//saves in-memory only
[GBStorageController save];					//syncs in-memory changes to disk
```

Reading:

```objective-c
GBStorageController[@"name"];				//returns "Luka", checks cache first, if not found reads from disk
```

Specific sync:
```objective-c
[GBStorage save:@"name"];					//syncs a specific key to disk
```

Preloading cache:
```objective-c
[GBStorage preload:@"bigObject"];			//asynchronously loads a specific key into memory for fast future access
```

Clear cache:
```objective-c
[GBStorage clearCache];						//Evicts entire in-memory cache, but leaves files on disk. e.g. in low memory situations
[GBStorage clearCacheForKey:@"name"];		//Evicts a single key from the in-memory cache
```

Deleting:
```objective-c
[GBStorage deletePermanently:@"bigObject"];	//deletes data from disk and cache
```

Storage
------------

Objects *stored* in the in-memory cache are simply retained with a strong pointer. If they could mutate it might be a good idea to pass in a copy to the `GBStorageController`. Once you've stored an object into `GBStorageController`, you CAN mutate the object but you have to keep in mind that the changes won't persist to disk until you call `[GBStorage save]`. Objects are not automatically copied for performance reasons.

Keys need to be of type `NSString`. They are automatically copied to avoid undefined behaviour if you were to mutate them.

Objects which you pass to `GBStorageController` must conform to the NSCoding protocol. This is so that objects can be serialised to disk.

Dependencies
------------

Add dependency, link, -ObjC linker flag, header search path in superproject.

* [GBToolbox](https://github.com/lmirosevic/GBToolbox)

Copyright & License
------------

Copyright 2013 Luka Mirosevic

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this work except in compliance with the License. You may obtain a copy of the License in the LICENSE file, or at:

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.