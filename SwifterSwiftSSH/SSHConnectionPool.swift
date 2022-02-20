//
//  SSHConnectionPool.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 20/12/2021.
//

import Foundation

struct SSHConnectionPoolStateObject: Identifiable {
    var activeRuns: Int = 0;
    var connection: SSHConnection;
    var id = UUID();
    var lastRun: DispatchTime;
}

actor SSHConnectionPoolState {
    var connections: [SSHConnectionPoolStateObject] = [];
    var maxConnections = 6;
    var normalConnections = 3;
    let options: SSHOption;
    
    init(options: SSHOption) {
        self.options = options;
    }
    
    func getConnection() async throws -> SSHConnectionPoolStateObject? {
        LogSSH("+ getConnection");
        if self.connections.filter({ $0.activeRuns == 0 }).count < 1, self.connections.count < self.maxConnections {
            connections.append(SSHConnectionPoolStateObject(activeRuns: 0, connection: try await SSHConnection(options: self.options), lastRun: .now()))
        }
        
        var connectionState = self.connections.sorted(by: { $0.activeRuns < $1.activeRuns }).first!;
        
        if connectionState.activeRuns > 0 {
            return nil;
        }
        
        connectionState.activeRuns += 1;
        
        self.connections = self.connections.map({ $0.id == connectionState.id ? connectionState : $0 });
        
        LogSSH("- getConnection \(connectionState.id) \(connectionState.activeRuns)");
        
        return connectionState;
    }
    
    func freeConnection(id: UUID) async {
        LogSSH("+ freeConnection");
        
        if let index = self.connections.firstIndex(where: { $0.id == id }) {
            self.connections[index].activeRuns -= 1;
            self.connections[index].lastRun = .now();
        }
        
        while (self.connections.count > self.normalConnections && self.connections.filter({ $0.activeRuns == 0 && $0.lastRun < .now() - 5 }).count > 0) {
            let toBeKilledConnection = self.connections.first(where: { $0.activeRuns == 0 && $0.lastRun < .now() - 5 })!;
            
            try? await toBeKilledConnection.connection.disconnect()
            
            self.connections.removeAll(where: { $0.id == toBeKilledConnection.id });
        }
        LogSSH("- freeConnection");
    }
    
    func removeConnection(id: UUID) async {
        LogSSH("+ removeConnection");
        
        if let index = self.connections.firstIndex(where: { $0.id == id }) {
            try? await self.connections[index].connection.disconnect();
            self.connections.remove(at: index);
        }
        
        LogSSH("- removeConnection");
    }
    
    func closeOldestStuckConnection() async {
        LogSSH("+ closeOldestStuckConnection");
        
        let connection = self.connections.sorted(by: { $0.activeRuns > $1.activeRuns && $0.lastRun > $1.lastRun }).first;
        
        if let connection = connection {
            await self.removeConnection(id: connection.id);
        }
        
        LogSSH("- closeOldestStuckConnection");
    }
    
    func disconnect() async {
        LogSSH("+ disconnect");
        for connectionState in self.connections {
            try? await connectionState.connection.disconnect();
        }
        self.connections.removeAll();
        LogSSH("- disconnect");
    }
}

class SSHConnectionPool {
    let pool: SSHConnectionPoolState;
    
    init(options: SSHOption) {
        self.pool = SSHConnectionPoolState(options: options);
    }
    
    public func exec(command: String) async throws -> SSHExecResult {
        return try await self.exec(command: command, delegate: nil);
    }
    
    public func exec(command: String, delegate: SSHExecDelegate?, notCancelable: Bool = false) async throws -> SSHExecResult {
        var connectionState = try await self.pool.getConnection()
        
        if connectionState == nil {
            let startWaitForConnection: DispatchTime = .now();
            
            while (connectionState == nil) {
                if startWaitForConnection < .now() - 3 {
                    await self.pool.closeOldestStuckConnection();
                }
                
                try await Task.sleep(nanoseconds: UInt64(pow(10.0, 9.0)));
                connectionState = try await self.pool.getConnection();
            }
        }
                
        let connection = connectionState!.connection;
        
        do {
            let result = try await Task<SSHExecResult, Error>.detached(priority: .background, operation: {
                return try await connection.exec(command: command, delegate: delegate, notCancelable: notCancelable)
            }).value;
                        
            await self.pool.freeConnection(id: connectionState!.id);
            
            return result;
        } catch {
            await self.pool.freeConnection(id: connectionState!.id);
            throw error;
        }
    }
    
    public func disconnect() async {
        await self.pool.disconnect();
    }
}
