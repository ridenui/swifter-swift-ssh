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
}

actor SSHConnectionPoolState {
    var connections: [SSHConnectionPoolStateObject] = [];
    var maxConnections = 4;
    var normalConnections = 2;
    let options: SSHOption;
    
    init(options: SSHOption) {
        self.options = options;
    }
    
    func getConnection() throws -> (connection: SSHConnection, id: UUID)? {
        LogSSH("+ getConnection");
        if self.connections.filter({ $0.activeRuns == 0 }).count < 1, self.connections.count < self.maxConnections {
            connections.append(SSHConnectionPoolStateObject(activeRuns: 0, connection: try SSHConnection(options: self.options)))
        }
        
        var connectionState = self.connections.sorted(by: { $0.activeRuns < $1.activeRuns }).first!;
        
        if connectionState.activeRuns > 0 {
            return nil;
        }
        
        connectionState.activeRuns += 1;
        
        self.connections = self.connections.map({ $0.id == connectionState.id ? connectionState : $0 });
        
        LogSSH("- getConnection \(connectionState.id) \(connectionState.activeRuns)");
        
        return (connection: connectionState.connection, id: connectionState.id);
    }
    
    func freeConnection(id: UUID) async {
        LogSSH("+ freeConnection");
        
        if let index = self.connections.firstIndex(where: { $0.id == id }) {
            self.connections[index].activeRuns -= 1;
        }
        
        while (self.connections.count > self.normalConnections && self.connections.filter({ $0.activeRuns == 0 }).count > 0) {
            let toBeKilledConnection = self.connections.first(where: { $0.activeRuns == 0 })!;
            
            await toBeKilledConnection.connection.disconnect();
            
            self.connections.removeAll(where: { $0.id == toBeKilledConnection.id });
        }
        LogSSH("- freeConnection");
    }
    
    func disconnect() async {
        LogSSH("+ disconnect");
        for connectionState in self.connections {
            await connectionState.connection.disconnect();
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
            while (connectionState == nil) {
                try await Task.sleep(nanoseconds: 10000);
                connectionState = try await self.pool.getConnection();
            }
        }
        
        let connection = connectionState!.connection;
        
        do {
            let result = try await connection.exec(command: command, delegate: delegate, notCancelable: notCancelable);
            
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
