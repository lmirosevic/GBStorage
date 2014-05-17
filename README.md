# GBStorageController ![Version](https://img.shields.io/cocoapods/v/GBStorageController.svg?style=flat)&nbsp;![License](https://img.shields.io/badge/license-Apache_2-green.svg?style=flat)

Simple iOS and Mac OS X persistence layer with in memory caching and preloading.

Usage
------------

Storing:

```objective-c
GBStorage[@"name"] = @"Luka";				//saves in-memory only
[GBStorage save];							//syncs in-memory changes to disk
```

Reading:

```objective-c
GBStorage[@"name"];							//returns "Luka", checks cache first, if not found reads from disk
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

Don't forget to import header, for iOS:

```objective-c
#import "GBStorageController.h"
```

... or on OSX:
```objective-c
#import <GBStorageController/GBStorageController.h>
```

Storage mechanics
------------

Objects *stored* in the in-memory cache are simply retained with a strong pointer. If they could mutate it might be a good idea to pass in a copy to the `GBStorageController`. Once you've stored an object into `GBStorageController`, you CAN mutate the object but you have to keep in mind that the changes won't persist to disk until you call `[GBStorage save]`. Objects are not automatically copied for performance reasons.

Keys need to be of type `NSString`. They are automatically copied to avoid undefined behaviour if you were to mutate them.

Objects which you pass to `GBStorageController` must conform to the NSCoding protocol. This is so that objects can be serialised to disk.

Dependencies
------------

* [GBToolbox](https://github.com/lmirosevic/GBToolbox)

iOS: Add to your project's workspace, add dependency for GBToolbox-iOS, link with your binary, add -ObjC linker flag, add header search path.

OS X: Add to your project's workspace, add dependency for GBToolbox-OSX, link with your binary, add "copy file" step to copy framework into bundle.

Copyright & License
------------

Copyright 2013 Luka Mirosevic

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this work except in compliance with the License. You may obtain a copy of the License in the LICENSE file, or at:

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/lmirosevic/gbstoragecontroller/trend.png)](https://bitdeli.com/free "Bitdeli Badge")
