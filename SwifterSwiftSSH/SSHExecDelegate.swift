//
//  SSHExecDelegate.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 21/12/2021.
//

import Foundation

public protocol SSHExecDelegate {
    var onStdout: ((_ data: String) -> Void)? { get set };
    
    var onStderr: ((_ data: String) -> Void)? { get set };
    
    var cancelFunction: ((_ cancelId: String) -> Void)? { get set };
}

public class SSHExecEventHandler: SSHExecDelegate {
    public init(onStdout: ((String) -> Void)? = nil, onStderr: ((String) -> Void)? = nil, cancelFunction: ((_ cancelId: String) -> Void)? = nil) {
        self.onStdout = onStdout
        self.onStderr = onStderr
        self.cancelFunction = cancelFunction
    }
    
    public var onStdout: ((String) -> Void)?
    
    public var onStderr: ((String) -> Void)?
    
    public var cancelFunction: ((_ cancelId: String) -> Void)?
}

