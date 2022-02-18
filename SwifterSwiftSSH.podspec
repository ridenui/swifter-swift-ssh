#
#  Be sure to run `pod spec lint swifter-swift-ssh.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see https://guides.cocoapods.org/syntax/podspec.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |spec|

  # ―――  Spec Metadata  ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  These will help people to find your library, and whilst it
  #  can feel like a chore to fill in it's definitely to your advantage. The
  #  summary should be tweet-length, and the description more in depth.
  #

  spec.name         = "SwifterSwiftSSH"
  spec.version = "1.1.12"
  spec.summary      = "A swift ssh client with libssh"

  # This description is used to generate tags and improve search results.
  #   * Think: What does it do? Why did you write it? What is the focus?
  #   * Try to keep it short, snappy and to the point.
  #   * Write the description between the DESC delimiters below.
  #   * Finally, don't worry about the indent, CocoaPods strips it!
  spec.description  = "This swift ssh client is build on top of libssh and uses swift's new async/await concurrency feature."
  spec.homepage     = "https://github.com/ridenui/swifter-swift-ssh"
  # spec.screenshots  = "www.example.com/screenshots_1.gif", "www.example.com/screenshots_2.gif"


  # ―――  Spec License  ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Licensing your code is important. See https://choosealicense.com for more info.
  #  CocoaPods will detect a license file if there is a named LICENSE*
  #  Popular ones are 'MIT', 'BSD' and 'Apache License, Version 2.0'.
  #

  spec.license      = { :type => "MIT", :file => "LICENSE" }


  # ――― Author Metadata  ――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Specify the authors of the library, with email addresses. Email addresses
  #  of the authors are extracted from the SCM log. E.g. $ git log. CocoaPods also
  #  accepts just a name if you'd rather not provide an email address.
  #
  #  Specify a social_media_url where others can refer to, for example a twitter
  #  profile URL.
  #

  spec.author             = { "Nils Bergmann" => "nilsbergmann@noim.io" }
  # Or just: spec.author    = "Nils Bergmann"
  # spec.authors            = { "Nils Bergmann" => "nilsbergmann@noim.io" }
  spec.social_media_url   = "https://twitter.com/EpicNilo"

  # ――― Platform Specifics ――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  If this Pod runs only on iOS or OS X, then specify the platform and
  #  the deployment target. You can optionally include the target after the platform.
  #

  # spec.platform     = :ios
  spec.platform     = :ios
  spec.platform     = :osx

  #  When using multiple platforms
  # spec.ios.deployment_target = "5.0"
  # spec.osx.deployment_target = "10.7"
  # spec.watchos.deployment_target = "2.0"
  # spec.tvos.deployment_target = "9.0"


  # ――― Source Location ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Specify the location from where the source should be retrieved.
  #  Supports git, hg, bzr, svn and HTTP.
  #

  spec.source       = { :git => "https://github.com/ridenui/swifter-swift-ssh.git", :tag => "#{spec.version}" }
  # spec.source = { :git => '.' }


  # ――― Source Code ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  CocoaPods is smart about how it includes source code. For source files
  #  giving a folder will include any swift, h, m, mm, c & cpp files.
  #  For header files it will include any header in the folder.
  #  Not including the public_header_files will make all headers public.
  #

  spec.source_files  = "SwifterSwiftSSH", "SwifterSwiftSSH/**/*.{h,m,swift}"
  # spec.public_header_files = "SwifterSwiftSSH/**/*.h"
  # spec.exclude_files = "Classes/Exclude"
  

  # spec.public_header_files = "Classes/**/*.h"


  # ――― Resources ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  A list of resources included with the Pod. These are copied into the
  #  target bundle with a build phase script. Anything else will be cleaned.
  #  You can preserve files from being cleaned, please don't preserve
  #  non-essential files like tests, examples and documentation.
  #

  # spec.resource  = "icon.png"
  # spec.resources = "Resources/*.png"

  # spec.preserve_paths = "FilesToSave", "MoreFilesToSave"
  spec.preserve_paths = "Libraries/lib/**/*.a", "Libraries-iOS/lib/**/*.a"

  # ――― Project Linking ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  Link your library with frameworks, or libraries. Libraries do not include
  #  the lib prefix of their name.
  #

  # spec.framework  = "SomeFramework"
  # spec.frameworks = "SomeFramework", "AnotherFramework"
  spec.framework    = 'CFNetwork'
  # spec.library      = 'z'

  spec.swift_version = '5.3'
  
  # spec.library   = "iconv"
  # spec.libraries = "z"


  # ――― Project Settings ――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  If your library depends on compiler flags you can set them in the xcconfig hash
  #  where they will only apply to your library. If you depend on other Podspecs
  #  you can include multiple dependencies to ensure it works.

  spec.requires_arc = true

  # spec.xcconfig = { "HEADER_SEARCH_PATHS" => "$(SDKROOT)/usr/include/libxml2" }
  # spec.dependency "JSONKit", "~> 1.4"
  
  spec.ios.deployment_target  = '13.0'
  spec.ios.vendored_libraries = 'Libraries-iOS/lib/libssh.a', 'Libraries-iOS/lib/libssl.a', 'Libraries-iOS/lib/libcrypto.a'
  # spec.ios.libraries          = "ssh", "ssl"
  spec.ios.source_files       = 'Libraries-iOS', 'Libraries-iOS/**/*.h'
  spec.ios.public_header_files  = 'Libraries-iOS/**/*.h'
  
  spec.osx.deployment_target  = '11.0'
  spec.osx.vendored_libraries = 'Libraries/lib/libssh.a', 'Libraries/lib/libssl.a', 'Libraries/lib/libcrypto.a'
  # spec.osx.libraries          = "ssh", "ssl"
  spec.osx.source_files       = 'Libraries', 'Libraries/**/*.h'
  spec.osx.public_header_files  = 'Libraries/**/*.h'
  
  spec.pod_target_xcconfig = { "DEFINES_MODULE" => "YES", 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
  
  spec.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
  
  spec.osx.header_mappings_dir = 'Libraries/include'
  spec.ios.header_mappings_dir = 'Libraries-iOS/include'
end
