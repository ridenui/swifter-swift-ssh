//
//  ExceptionsHandler.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 27/02/2022.
//

import Foundation

// https://stackoverflow.com/questions/16202029/is-there-a-way-to-catch-or-handle-exc-bad-access
class ExceptionHandler {
    private static var isReady = false
    
    init() {
        if !Self.isReady {
            Self.isReady = true
            signal_catch_init()
        }
    }
    
    private func cFunction(_ block: @escaping @convention(block) () -> Void) -> (@convention(c) () -> Void) {
        return unsafeBitCast(imp_implementationWithBlock(block), to: (@convention(c) () -> Void).self)
    }
    
    func execute(_ block: @escaping () -> Void) throws {
        class Context {
            public let callback: () -> Void;
            
            init(callback: @escaping () -> Void) {
                self.callback = callback;
            }
            
            deinit {
                // LogSSH("Deinit Context")
            }
        }
        
        let contextData = Context(callback: block);
        
        let contextPtr = unsafeBitCast(contextData, to: UnsafeMutableRawPointer.self);
        
        let error = signalTry({ newContext in
            guard let newContext = newContext else {
                // LogSSH("No context")
                return;
            }
            
            let localContext = Unmanaged<Context>.fromOpaque(newContext).takeUnretainedValue();
            
            // LogSSH("Call callback")
            
            localContext.callback();
        }, contextPtr)

        if let error = error, !String(cString: UnsafePointer<CChar>(error)).isEmpty {
            print("Catched signal \(String(cString: UnsafePointer<CChar>(error)))")
            throw NSError(domain: String(cString: UnsafePointer<CChar>(error)), code: 1, userInfo: nil);
        }
    }
}
