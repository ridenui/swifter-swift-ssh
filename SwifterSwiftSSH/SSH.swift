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
        return try await self.exec(command: command, delegate: nil);
    }
    
    public func exec(command: String, delegate: SSHExecDelegate?, notCancelable: Bool = false) async throws -> SSHExecResult {
        return try await self.pool.exec(command: command, delegate: delegate, notCancelable: notCancelable);
    }
    
    public func cancel(id: String) async throws {
        let result = try await self.pool.exec(command: """
            kill_descendant_processes() {
                local pid="$1"
                local and_self="${2:-false}"
                if children="$(pgrep -P "$pid")"; then
                    for child in $children; do
                        kill_descendant_processes "$child" true
                    done
                fi
                if [[ "$and_self" == true ]]; then
                    kill -9 "$pid"
                fi
            }
            if [[ -f /tmp/\(id)-parent.pid ]]; then
                kill_descendant_processes `cat /tmp/\(id)-parent.pid` true
            fi
            if [[ -f /tmp/\(id)-parent.pid ]]; then
                rm /tmp/\(id)-parent.pid 2>/dev/null
            fi
        """, delegate: nil, notCancelable: true)
        LogSSH("Cancel result \(result)")
        return;
    }
}
