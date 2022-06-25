//
//  swifter_swift_ssh.swift
//  swifter-swift-ssh
//
//  Created by Nils Bergmann on 17.12.21.
//
import Foundation

/// SSH Connection
/// This class automatically manages a connection pool to run multiple commands at the same time
public class SSH {
    
    private var pool: SSHConnectionPool;
    private var options: SSHOption;
    
    /// Initialize the SSH Connection class
    /// - Parameter options: Options required for a SSH connection
    /// - Note: At this moment no SSH connection is active
    public init(options: SSHOption) {
        self.options = options;
        self.pool = SSHConnectionPool(options: options);
    }
    
    /// Disconnect the underlying SSH pool
    public func disconnect() async {
        return await SSHLogger.shared.startNewLoggingContext({
            await self.pool.disconnect();
        })
    }
    
    /// Execute a command in the SSH connection pool
    /// - Parameter command: Command to execute on the remote host
    /// - Returns: `SSHExecResult` containing the result of the execution
    public func exec(command: String) async throws -> SSHExecResult {
        return try await self.exec(command: command, delegate: nil);
    }
    
    /// Execute a command in the SSH connection pool
    /// - Parameters:
    ///   - command: Command to execute on the remote host
    ///   - delegate: Events like `SSHExecDelegate.onStdout` or `SSHExecDelegate.onStderr` get called on this object. This can provide realtime features
    ///   - notCancelable: If this is true, the required command wrapper which is needed for `cancel(id:)` doesn't get add. This parameter is optional and normally you should leave it alone
    /// - Returns: SSHExecResult containing the result of the execution
    public func exec(command: String, delegate: SSHExecDelegate?, notCancelable: Bool = false) async throws -> SSHExecResult {
        return try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<SSHExecResult, Error>) in
            Task {
                do {
                    continuation.resume(returning: try await SSHLogger.shared.startNewLoggingContext({
                        return try await self.pool.exec(command: command, delegate: delegate, notCancelable: notCancelable);
                    }))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        })
    }
    
    /// Cancel a command on the remote machine
    /// - Parameter id: Id of the command which gets passed in the `SSHExecDelegate.cancelFunction` method of the `SSHExecDelegate` in `exec(command:delegate:notCancelable:)`
    /// - Warning: If the ssh pool is satisfied, this function doesn't return until a connection gets freed up
    public func cancel(id: String) async throws {
        Task.detached {
            return try await SSHLogger.shared.startNewLoggingContext({
                SSHLogger.shared.openLog("SSHCancel")
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
                                echo "Killed"
                            """, delegate: nil, notCancelable: true)
                SSHLogger.shared.closeLog("SSHCancel", attributes: ["result": "\(result)"])
            })
        }
        return;
    }
}
