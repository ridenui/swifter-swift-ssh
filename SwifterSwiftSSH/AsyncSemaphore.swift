//
//  AsyncSemaphore.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 23.12.21.
//

import Foundation

actor AsyncSemaphore {
    var finished = false;
    
    func finish() {
        LogSSH("Finish async semaphore")
        self.finished = true;
    }
    
    func isFinished(by deadline: DispatchTime) -> Bool {
        if deadline < DispatchTime.now() {
            return true;
        } else {
            return self.finished;
        }
    }
}
