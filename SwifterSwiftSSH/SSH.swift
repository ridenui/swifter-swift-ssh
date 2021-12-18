//
//  swifter_swift_ssh.swift
//  swifter-swift-ssh
//
//  Created by Nils Bergmann on 17.12.21.
//
import Foundation

public class SSH {

    private var session: ssh_session?;
    private let options: SSHOption;
    private var ssh_connected: Bool = false;
    private let dispatchQueue = DispatchQueue(label: "swifter-ssh")
    private let connectionLock = NSLock();
    private let sessionLock = NSLock();
    
    init(options: SSHOption) {
        self.options = options;
    }
    
    private func initSession() {
        self.sessionLock.lock();
        self.session = ssh_new();
        
        var port = options.port;
        
        if self.session != nil {
            ssh_options_set(self.session, SSH_OPTIONS_HOST, options.host);
            ssh_options_set(self.session, SSH_OPTIONS_PORT, &port);
        }
        self.sessionLock.unlock();
    }
    
    public func connect() async throws {
        self.connectionLock.lock();
        if self.session == nil {
            self.initSession();
            
            if self.session == nil {
                self.connectionLock.unlock();
                throw SSHError.CAN_NOT_OPEN_SESSION;
            }
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.dispatchQueue.async {
                let rc = ssh_connect(self.session);
                if rc != SSH_OK {
                    let errorString = String(cString: ssh_get_error(&self.session));
                    continuation.resume(throwing: SSHError.CONNECTION_ERROR(errorString));
                    self.connectionLock.unlock();
                } else {
                    self.ssh_connected = true;
                    continuation.resume();
                }
            }
        }
        
        try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Void, Error>) in
            self.dispatchQueue.async {
                let ra = ssh_userauth_password(self.session, self.options.username, self.options.password);
                if ra == SSH_AUTH_SUCCESS.rawValue {
                    continuation.resume();
                } else if ra == SSH_AUTH_DENIED.rawValue {
                    continuation.resume(throwing: SSHError.AUTH_DENIED);
                    self.connectionLock.unlock();
                } else if ra == SSH_AUTH_ERROR.rawValue {
                    continuation.resume(throwing: SSHError.AUTH_ERROR);
                    self.connectionLock.unlock();
                } else {
                    continuation.resume(throwing: SSHError.AUTH_ERROR_OTHER(ssh_auth_e(ra)));
                    self.connectionLock.unlock();
                }
            }
        })
        
        self.connectionLock.unlock();
    }
    
    public func isConnected() async -> Bool {
        self.connectionLock.lock();
        if self.session == nil {
            self.connectionLock.unlock();
            return false;
        }
        
        let result = await withCheckedContinuation({ (continuation: CheckedContinuation<Bool, Never>) in
            self.dispatchQueue.async {
                let rc = ssh_is_connected(self.session);
                if rc > 0 {
                    continuation.resume(returning: true);
                } else {
                    continuation.resume(returning: false);
                }
            }
        })
        self.connectionLock.unlock();
                                                       
        return result;
    }
    
    public func disconnect() async {
        self.connectionLock.lock();
        if self.session == nil {
            self.connectionLock.unlock();
            return;
        }
        
        await withCheckedContinuation({ (continuation: CheckedContinuation<Void, Never>) in
            self.dispatchQueue.async {
                ssh_disconnect(self.session);
                ssh_free(self.session);
                self.session = nil;
                continuation.resume();
            }
        })
        self.connectionLock.unlock();
                                                       
        return;
    }
    
    public func exec(command: String) async throws -> SSHExecResult {
        if !(await self.isConnected()) {
            try await self.connect();
        }
                
        let channel = try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<ssh_channel, Error>) in
            self.dispatchQueue.async {
                let channel = ssh_channel_new(self.session);
                if channel == nil {
                    continuation.resume(throwing: SSHError.CAN_NOT_OPEN_CHANNEL);
                    return;
                }
                let rc = ssh_channel_open_session(channel);
                
                if rc == SSH_OK {
                    continuation.resume(returning: channel!);
                } else {
                    ssh_channel_free(channel);
                    continuation.resume(throwing: SSHError.CAN_NOT_OPEN_CHANNEL_SESSION);
                }
            }
        });
        
        let exitCode = try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Int32, Error>) in
            self.dispatchQueue.async {
                let rc = ssh_channel_request_exec(channel, command);
                if rc == SSH_OK {
                    continuation.resume(returning: 0);
                    return;
                } else {
                    Task<Void, Never> {
                        let errorCode = await withUnsafeContinuation { (continuation: UnsafeContinuation<Int32, Never>) in
                            self.dispatchQueue.asyncAfter(deadline: .now() + 3) {
                                continuation.resume(returning: ssh_channel_get_exit_status(channel));
                            }
                            continuation.resume(returning: 1);
                        }
                        continuation.resume(returning: errorCode);
                    }
                }
            }
        })
        
        
        async let stdoutAsync = withCheckedContinuation({ (continuation: CheckedContinuation<String, Never>) in
            self.dispatchQueue.async {
                var data = "";
                let buffer = UnsafeMutablePointer<Int8>(mutating: ("" as NSString).utf8String)
                while (ssh_channel_read(channel, buffer, 1024, 0) > 0) {
                    if buffer != nil {
                        data.append(contentsOf: String(cString: buffer!));
                    }
                }
                continuation.resume(returning: data);
            }
        });
        
        async let stderrAsync = withCheckedContinuation({ (continuation: CheckedContinuation<String, Never>) in
            self.dispatchQueue.async {
                var data = "";
                let buffer = UnsafeMutablePointer<Int8>(mutating: ("" as NSString).utf8String)
                while (ssh_channel_read(channel, buffer, 1024, 1) > 0) {
                    if buffer != nil {
                        data.append(contentsOf: String(cString: buffer!));
                    }
                }
                continuation.resume(returning: data);
            }
        });
        
        let outArray = await [stdoutAsync, stderrAsync];
        
        return SSHExecResult(stdout: outArray[0], stderr: outArray[1], exitCode: exitCode, exitSignal: nil);
    }
    
    deinit {
        self.connectionLock.lock();
        if self.session != nil {
            ssh_free(self.session);
            self.session = nil;
        }
        self.connectionLock.unlock();
    }
}
