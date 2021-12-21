//
//  swifter_swift_ssh.swift
//  swifter-swift-ssh
//
//  Created by Nils Bergmann on 17.12.21.
//
import Foundation

public class SSH {

    private var pool: SSHConnectionPool;
    private var options: SSHOption;
    
    public init(options: SSHOption) {
        self.options = options;
        self.pool = SSHConnectionPool(options: options);
    }
    
    public func disconnect() async {
        await self.pool.disconnect();
    }
    
    public func exec(command: String) async throws -> SSHExecResult {
        return try await self.pool.exec(command: command);
    }
}
