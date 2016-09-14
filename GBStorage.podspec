Pod::Spec.new do |s|
  s.name         = 'GBStorage'
  s.version      = '2.6.0'
  s.summary      = 'Simple iOS and Mac OS X persistence layer with in-memory caching, optional persistence, pre-loading, namespacing and a sweet syntax.'
  s.homepage     = 'https://github.com/lmirosevic/GBStorage'
  s.license      = 'Apache License, Version 2.0'
  s.author       = { 'Luka Mirosevic' => 'luka@goonbee.com' }
  s.ios.deployment_target = '5.0'
  s.osx.deployment_target = '10.7'
  s.source       = { git: 'https://github.com/lmirosevic/GBStorage.git', tag: s.version.to_s }
  s.source_files  = 'GBStorage.{h,m}'
  s.public_header_files = 'GBStorage.h'
  s.requires_arc = true
end
