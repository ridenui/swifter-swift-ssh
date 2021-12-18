#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "../../SwifterSwiftSSH/swifter-swift-ssh-Bridging-Header.h"
#import "../../SwifterSwiftSSH/swifter-swift-ssh-macos-Bridging-Header.h"
#import "libssh/callbacks.h"
#import "libssh/legacy.h"
#import "libssh/libssh.h"
#import "libssh/libssh_version.h"
#import "libssh/ssh2.h"

FOUNDATION_EXPORT double SwifterSwiftSSHVersionNumber;
FOUNDATION_EXPORT const unsigned char SwifterSwiftSSHVersionString[];

