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

class SSHConnectionPoolState {
    var connections: [SSHConnectionPoolStateObject] = [];
    var maxConnections = 6;
    var normalConnections = 3;
    let options: SSHOption;
    let lock: NSLock = NSLock();
    
    init(options: SSHOption) {
        self.options = options;
    }
    
    func getConnection() async throws -> SSHConnectionPoolStateObject? {
        SSHLogger.shared.openLog("SSHConnectionPoolStateGetConnection", attributes: ["count": self.connections.count])
        defer {
            SSHLogger.shared.closeLog("SSHConnectionPoolStateGetConnection", attributes: ["count": self.connections.count])
        }
        self.lock.lock();
        defer {
            self.lock.unlock()
        }
        if self.connections.filter({ $0.activeRuns == 0 }).count < 1, self.connections.count < self.maxConnections {
            connections.append(SSHConnectionPoolStateObject(activeRuns: 0, connection: try await SSHConnection(options: self.options), lastRun: .now()))
        }
                
        var connectionState = self.connections.sorted(by: { $0.activeRuns < $1.activeRuns }).first!;
        
        if connectionState.activeRuns > 0 {
            return nil;
        }
        
        connectionState.activeRuns += 1;
        
        self.connections = self.connections.map({ $0.id == connectionState.id ? connectionState : $0 });
        
        SSHLogger.shared.midLog("SSHConnectionPoolStateGetConnection", attributes: ["id": connectionState.id, "activeRuns": connectionState.activeRuns, "count": self.connections.count])
                
        return connectionState;
    }
    
    func freeConnection(id: UUID, invalidate: Bool = false) async {
        SSHLogger.shared.openLog("SSHConnectionPoolStateFreeConnection", attributes: ["id": id, "invalidate": invalidate])
        self.lock.lock();
        defer {
            SSHLogger.shared.closeLog("SSHConnectionPoolStateFreeConnection")
            self.lock.unlock()
        }
        
        if var connection = self.connections.first(where: { $0.id == id }) {
            connection.activeRuns -= 1;
            connection.lastRun = .now();
            self.connections = self.connections.map({ $0.id == connection.id ? connection : $0 });
            if invalidate {
                self.connections.removeAll(where: { $0.id == id })
            }
        }
        
        while (self.connections.count > self.normalConnections && self.connections.filter({ $0.activeRuns == 0 && $0.lastRun < .now() - 5 }).count > 0) {
            let toBeKilledConnection = self.connections.first(where: { $0.activeRuns == 0 && $0.lastRun < .now() - 5 })!;
            
            try? await toBeKilledConnection.connection.disconnect()
            
            self.connections.removeAll(where: { $0.id == toBeKilledConnection.id });
        }
    }
    
    func removeConnection(id: UUID, lock: Bool = true) async {
        SSHLogger.shared.openLog("SSHConnectionPoolStateRemoveConnection", attributes: ["id": id, "lock": lock])
        if lock {
            self.lock.lock();
        }
        defer {
            SSHLogger.shared.closeLog("SSHConnectionPoolStateRemoveConnection")
            if lock {
                self.lock.unlock()
            }
        }
        
        if let connection = self.connections.first(where: { $0.id == id }) {
            try? await connection.connection.disconnect();
            self.connections.removeAll(where: { $0.id == id })
        }
    }
    
    func closeOldestStuckConnection() async {
        SSHLogger.shared.openLog("SSHConnectionPoolStateCloseOldestStuckConnection")
        self.lock.lock();
        defer {
            SSHLogger.shared.closeLog("SSHConnectionPoolStateCloseOldestStuckConnection")
            self.lock.unlock()
        }
        
        let connection = self.connections.sorted(by: { $0.activeRuns > $1.activeRuns && $0.lastRun > $1.lastRun }).first;
        
        if let connection = connection {
            await self.removeConnection(id: connection.id, lock: false);
        }
    }
    
    func disconnect() async {
        SSHLogger.shared.openLog("SSHConnectionPoolStateDisconnect")
        self.lock.lock();
        defer {
            SSHLogger.shared.closeLog("SSHConnectionPoolStateDisconnect")
            self.lock.unlock()
        }
        for connectionState in self.connections {
            try? await connectionState.connection.disconnect();
        }
        self.connections.removeAll();
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
        SSHLogger.shared.openLog("SSHConnectionPoolExec", attributes: ["cmd": command])
        defer {
            SSHLogger.shared.closeLog("SSHConnectionPoolExec", attributes: ["cmd": command])
        }
        
        var connectionState = try await self.pool.getConnection()
        
        if connectionState == nil {
            let startWaitForConnection: DispatchTime = .now();
            
            SSHLogger.shared.midLog("SSHConnectionPoolExec", attributes: ["msg": "No connection available. Wait for one", "cmd": command])
                        
            while (connectionState == nil) {
                if startWaitForConnection < .now() - 6 {
                    await self.pool.closeOldestStuckConnection();
                }
                
                try await Task.sleep(nanoseconds: UInt64(pow(10.0, 9.0)));
                connectionState = try await self.pool.getConnection();
            }
        }
                
        let connection = connectionState!.connection;
        
        SSHLogger.shared.midLog("SSHConnectionPoolExec", attributes: ["msg": "Exec now", "cmd": command])
                
        do {
            let taskId = SSHLogger.shared.getTaskId();
            let result = try await Task<SSHExecResult, Error>.detached(priority: .background, operation: {
                return try await SSHLogger.$taskId.withValue(taskId, operation: {
                    return try await connection.exec(command: command, delegate: delegate, notCancelable: notCancelable)
                })
            }).value;
                        
            await self.pool.freeConnection(id: connectionState!.id);
            
            return result;
        } catch {
            await self.pool.freeConnection(id: connectionState!.id, invalidate: true);
            throw error;
        }
    }
    
    public func disconnect() async {
        SSHLogger.shared.openLog("SSHConnectionPoolDisconnect")
        defer {
            SSHLogger.shared.closeLog("SSHConnectionPoolDisconnect")
        }
        await self.pool.disconnect();
    }
}
