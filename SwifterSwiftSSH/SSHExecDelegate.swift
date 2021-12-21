//
//  SSHExecDelegate.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 21/12/2021.
//

import Foundation

/// This protocol enables realtime features for remote command execution
public protocol SSHExecDelegate {
    /// Gets called if new data on stdout is available.
    /// - Note: This is not per line
    var onStdout: ((_ data: String) -> Void)? { get set };
    
    /// Gets called if new data on stderr is available.
    /// - Note: This is not per line
    var onStderr: ((_ data: String) -> Void)? { get set };
    
    /// Gets called if the id required for `SSH.cancel` is available
    /// - Warning: There is a chance this never gets called
    var cancelFunction: ((_ cancelId: String) -> Void)? { get set };
}

/// This is a quick way to get an object conforming to `SSHExecDelegate`
public class SSHExecEventHandler: SSHExecDelegate {
    /// Initializes the event object
    /// - Parameters:
    ///   - onStdout: See `SSHExecDelegate.onStdout`
    ///   - onStderr: See `SSHExecDelegate.onStderr`
    ///   - cancelFunction: See `SSHExecDelegate.cancelFunction`
    public init(onStdout: ((String) -> Void)? = nil, onStderr: ((String) -> Void)? = nil, cancelFunction: ((_ cancelId: String) -> Void)? = nil) {
        self.onStdout = onStdout
        self.onStderr = onStderr
        self.cancelFunction = cancelFunction
    }
    
    /// See `SSHExecDelegate.onStdout`
    public var onStdout: ((String) -> Void)?
    
    /// See `SSHExecDelegate.onStderr`
    public var onStderr: ((String) -> Void)?
    
    /// See `SSHExecDelegate.cancelFunction`
    public var cancelFunction: ((_ cancelId: String) -> Void)?
}

