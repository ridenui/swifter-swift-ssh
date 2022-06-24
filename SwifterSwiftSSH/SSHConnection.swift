//
//  SSHConnection.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 20/12/2021.
//

import Foundation

var cmdId: Int = 0;

actor AsyncSemaphore {
    private var dispatched = false;
    
    func signal() {
        dispatched = true;
    }
    
    /// Doesn't actually wait
    /// Just indicates, if signal was called
    func wait() -> Bool {
        return dispatched
    }
}

class SSHConnection {
    private let options: SSHOption;
    private var session: SSHSession;
    
    public init(options: SSHOption) async throws {
        self.options = options;
                
        self.session = try await SSHSession(options: self.options);
    }
    
    public func connect() async throws {
        try await self.session.connect();
    }
    
    public func disconnect() async throws {
        try await self.session.disconnect();
    }
    
    func exec(command: String) async throws -> SSHExecResult {
        return try await self.exec(command: command, delegate: nil);
    }
    
    func exec(command: String, delegate: SSHExecDelegate?) async throws -> SSHExecResult {
        return try await self.exec(commandInput: command, delegate: delegate, notCancelable: false);
    }
    
    func exec(command: String, delegate: SSHExecDelegate?, notCancelable: Bool = false) async throws -> SSHExecResult {
        return try await self.exec(commandInput: command, delegate: delegate, notCancelable: notCancelable);
    }
    
    func exec(commandInput: String, delegate: SSHExecDelegate?, notCancelable: Bool = false) async throws -> SSHExecResult {
        var command = commandInput;
        let commandUUID = UUID().uuidString;
        if !notCancelable {
            let cmd64 = Data(command.utf8).base64EncodedString();
            
            command = """
                bash -c "eval \\`echo \"\(cmd64)\" | base64 --decode\\`" &
                PID=$!
                echo $$ > /tmp/\(commandUUID)-parent.pid
                wait $PID
                EXIT_CODE=$?
                if [[ -f /tmp/\(commandUUID)-parent.pid ]]; then
                    rm /tmp/\(commandUUID)-parent.pid
                fi
                exit $EXIT_CODE
            """
            
            LogSSH("New command: \(command)");
        }
        try await self.session.connect();
        
        let semaphoreExit = AsyncSemaphore();
        let semaphoreExitSignal = AsyncSemaphore();
        let semaphoreStd = AsyncSemaphore();
        
        var exitStatusResult: Int?;
        var exitSignalResult: String?;
        
        await self.session.setCallbacks { exitStatus in
            LogSSH("Received exitStatus \(exitStatus)")
            exitStatusResult = Int(exitStatus);
            Task.detached {
                await semaphoreExit.signal()
            }
        } exitSignal: { signal, core, errmsg in
            LogSSH("Received exitSignal \(signal)")
            exitSignalResult = signal;
            Task.detached {
                await semaphoreExitSignal.signal();
                await semaphoreExit.signal();
            }
        }

        try await self.session.requestExec(command: command);
        
        if let delegate = delegate {
            if let cancelFunction = delegate.cancelFunction {
                cancelFunction(commandUUID);
            } else {
                LogSSH("cancelFunction is nil")
            }
        } else {
            LogSSH("delegate is nil")
        }
        
        typealias ReturningType = (out: String, err: String);
        
        let result = try await withThrowingTaskGroup(of: Any.self, returning: ReturningType.self, body: { taskGroup in
            taskGroup.addTask {
                typealias ReadResult = (read: Int32, std: String?);
                var readStd: ReadResult = try await self.session.readNonBlocking();
                var readErr: ReadResult = try await self.session.readNonBlocking(stderr: true);
                var readErrors = 5;
                
                var std: (std: String, err: String) = ("", "");
                
                while ((readErr.read >= 0 && readStd.read >= 0) || readErrors > 0) {
                    if (readStd.read < 0 && readStd.read != SSH_EOF) || (readErr.read < 0 && readErr.read != SSH_EOF) {
                        readErrors -= 1;
                    }
                    
                    if readStd.read > 0, readStd.std != nil {
                        std.std += readStd.std!;
                        if let delegate = delegate {
                            if let onStdout = delegate.onStdout {
                                onStdout(readStd.std!);
                            }
                        }
                    }
                    
                    if readErr.read > 0, readErr.std != nil {
                        std.err += readErr.std!;
                        if let delegate = delegate {
                            if let onStderr = delegate.onStderr {
                                onStderr(readErr.std!);
                            }
                        }
                    }
                    
                    if readErr.read == SSH_EOF, readStd.read == SSH_EOF {
                        break;
                    }
                    
                    try await Task.sleep(nanoseconds: 5000);
                    
                    readStd = try await self.session.readNonBlocking();
                    readErr = try await self.session.readNonBlocking(stderr: true);
                }
                            
                LogSSH("Std read finished")
                
                await semaphoreStd.signal();
                
                return (out: std.std, err: std.err);
            }
            
            taskGroup.addTask {
                while (!(await semaphoreExit.wait())) {
                    try await Task.sleep(nanoseconds: 10000);
                }
                LogSSH("semaphoreExit finished")
                while (!(await semaphoreStd.wait())) {
                    try await Task.sleep(nanoseconds: 10000);
                }
                LogSSH("semaphoreStd finished")
                let end: DispatchTime = .now() + 0.1;
                while (!(await semaphoreExitSignal.wait()) && end > .now()) {
                    try await Task.sleep(nanoseconds: 10000);
                }
                LogSSH("Semaphores finished")
                return 0;
            }
            
            let stdResult = try await taskGroup.next();
            let _ = try await taskGroup.next();
            
            return stdResult as! ReturningType;
        });
        
        try await self.session.closeChannel();
                
        return SSHExecResult(stdout: result.out, stderr: result.err, exitCode: Int32(exitStatusResult ?? -15), exitSignal: exitSignalResult);
    }
}
