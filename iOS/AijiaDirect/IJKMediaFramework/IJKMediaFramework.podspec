Pod::Spec.new do |s|
  s.name         = 'IJKMediaFramework'
  s.version      = '0.8.8'
  s.summary      = 'IJKMediaFramework (ijkplayer k0.8.8 fork with record support)'
  s.homepage     = 'https://github.com/bilibili/ijkplayer'
  s.license      = { :type => 'LGPL-2.1' }
  s.author       = { 'Bilibili' => 'bbcallen@gmail.com' }
  s.platform     = :ios, '9.0'
  s.source       = { :path => '.' }
  s.vendored_frameworks = 'IJKMediaFramework.framework'
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreGraphics', 'CoreMedia',
                  'CoreVideo', 'MediaPlayer', 'MobileCoreServices', 'OpenGLES',
                  'QuartzCore', 'UIKit', 'VideoToolbox'
  s.libraries = 'z', 'bz2', 'c++'
end
