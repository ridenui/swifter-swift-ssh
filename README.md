#  SwifterSwiftSSH

![Pod Version](https://img.shields.io/cocoapods/v/SwifterSwiftSSH?style=for-the-badge) ![License](https://img.shields.io/cocoapods/l/SwifterSwiftSSH?style=for-the-badge) [![Docs](https://img.shields.io/badge/-Docs-blueviolet?style=for-the-badge)](https://ssh.ridenui.org) [![MIT license](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](https://lbesson.mit-license.org/)


### Requirements

- XCode >= 13.2.1
- Swift Toolchain >= 5.5.2

### Basic usage

Podfile:

```pod
pod 'SwifterSwiftSSH'
```

Swift:

```swift
import SwifterSwiftSSH

// ...

let options = SSHOption(host: host, port: port, username: username, password: password);

let ssh = SSH(option: options);

let result = try await ssh.exec("ls -lah");

print(result.stdout);
```
