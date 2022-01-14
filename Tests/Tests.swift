//
//  Tests.swift
//  Tests
//
//  Created by Nils Bergmann on 19/12/2021.
//

import XCTest
#if canImport(SwifterSwiftSSH_macos)
@testable import SwifterSwiftSSH_macos
#else
@testable import SwifterSwiftSSH
#endif

class Tests: XCTestCase {
    
    var sshConfig: SSHOption?;
    
    var connectionType: String?;
        
    override func setUpWithError() throws {
        guard let path = Bundle(for: type(of: self)).path(forResource: "credentials", ofType: "plist") else {
            throw TestErrors.MISSING_CREDENTIALS;
        }
        guard let credentialsDictionary = NSDictionary(contentsOfFile: path) else {
            throw TestErrors.INVALID_CREDENTIALS_PLIST;
        }
        guard let host = credentialsDictionary["host"] as? String else {
            throw TestErrors.MISSING_HOST;
        }
        guard let username = credentialsDictionary["username"] as? String else {
            throw TestErrors.MISSING_USERNAME;
        }
        guard let password = credentialsDictionary["password"] as? String else {
            throw TestErrors.MISSING_PASSWORD;
        }
        let connectionType = credentialsDictionary["type"] as? String;
        self.connectionType = connectionType ?? "mac";
        
        let port = credentialsDictionary["port"] as? Int ?? 22;
        
#if canImport(SwifterSwiftSSH_macos)
        self.sshConfig = SSHOption(host: host, port: port, username: username, password: password);
#else
        let folderURL = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let knownHostFile = folderURL.appendingPathComponent("known_hosts")
        let idLocation = folderURL.appendingPathComponent("id_rsa")
        
        let keyPair = try generateRSAKeyPair();
        
        if !FileManager.default.fileExists(atPath: idLocation.path) {
            try keyPair.privateKey.write(toFile: idLocation.path, atomically: true, encoding: .utf8);
        }
        
        self.sshConfig = SSHOption(host: host, port: port, username: username, password: password, knownHostFile: knownHostFile.path, idRsaLocation: idLocation.path);
#endif
    }
    
    func testConnectionActor() async throws {
        guard let sshConfig = sshConfig else {
            throw TestErrors.CONFIG_IS_NIL
        }
        
        let ssh = await try SSHConnection(options: sshConfig);
        
        let outputString = "Hello world!"
        
        let result = try await ssh.exec(command: "echo \"\(outputString)\"");
        
        print(result);
                
        XCTAssert(result.exitCode == 0, "Return code should be 0");
        
        XCTAssert(result.stdout == "\(outputString)\n", "Result stdout should match output");
        
        await ssh.disconnect();
    }
    
    func testHelloWorldCommand() async throws {
        guard let sshConfig = sshConfig else {
            throw TestErrors.CONFIG_IS_NIL
        }

        let ssh = SSH(options: sshConfig);
                
        let outputString = "Hello world!"
        
        let result = try await ssh.exec(command: "echo \"\(outputString)\"");
        
        print(result);
                
        XCTAssert(result.exitCode == 0, "Return code should be 0");
        
        XCTAssert(result.stdout == "\(outputString)\n", "Result stdout should match output");
        
        await ssh.disconnect();
    }
    
    func testReturnCode() async throws {
        guard let sshConfig = sshConfig else {
            throw TestErrors.CONFIG_IS_NIL
        }

        let ssh = SSH(options: sshConfig);
        
        let outputString = "Hello world!"
        
        let result = try await ssh.exec(command: "echo \"\(outputString)\"; exit 15;");
        print(result);
        
        XCTAssert(result.exitCode == 15, "Return code should be 15");
        
        XCTAssert(result.stdout == "\(outputString)\n", "Result stdout should match output");
        
        await ssh.disconnect();
    }
    
    func testParallelExecution() async throws {
        guard let sshConfig = sshConfig else {
            throw TestErrors.CONFIG_IS_NIL
        }

        let ssh = SSH(options: sshConfig);
                
        // Command 1
        
        let outputString1 = "Hello world!"
        let outputStderr1 = "Error world!"
        let exitCode1 = 15;
        let runCount1 = 5;

        async let command1 = ssh.exec(command: "for i in {1..\(runCount1)}; do echo \"\(outputString1)\"; echo \"\(outputStderr1)\" >&2; sleep 1; done; exit \(exitCode1);");
                

        // Command 2

        let outputString2 = "Bye world!"
        let outputStderr2 = "Cruel world!"
        let exitCode2 = 10;
        let runCount2 = 4;

        async let command2 = ssh.exec(command: "for i in {1..\(runCount2)}; do echo \"\(outputString2)\"; echo \"\(outputStderr2)\" >&2; sleep 1; done; exit \(exitCode2);");

        // Run both commands in parallel
        let results = try await [command1, command2];

        // Test Command 1
        let result1 = results.first!;
        print(result1)
        XCTAssert(result1.exitCode == exitCode1, "Return code should be \(exitCode1)");
        XCTAssert(result1.stdout == String(repeating: "\(outputString1)\n", count: runCount1), "Stdout should be '\(outputString1)' \(runCount1) times");
        XCTAssert(result1.stderr == String(repeating: "\(outputStderr1)\n", count: runCount1), "Stderr should be '\(outputStderr1)' \(runCount1) times");

        // Test Command 2
        let result2 = results.last!;
        print(result2)
        XCTAssert(result2.exitCode == exitCode2, "Return code should be \(exitCode2)");
        XCTAssert(result2.stdout == String(repeating: "\(outputString2)\n", count: runCount2), "Stdout should be '\(outputString2)' \(runCount2) times");
        XCTAssert(result2.stderr == String(repeating: "\(outputStderr2)\n", count: runCount2), "Stderr should be '\(outputStderr2)' \(runCount2) times");
        
        await ssh.disconnect();
    }
    
    func testCancelAndDelegate() async throws {
        guard let sshConfig = sshConfig else {
            throw TestErrors.CONFIG_IS_NIL
        }
        
        let uuid = UUID().uuidString;

        let ssh = SSH(options: sshConfig);
        
        actor Canceled {
            var canceled = false;
            
            func setCanceled(to: Bool) {
                self.canceled = to;
            }
        }
        
        let canceled = Canceled();
        
        let delegate = SSHExecEventHandler { stdout in
            print("stdout: \(stdout)");
        } onStderr: { stderr in
            print("stderr: \(stderr)");
        } cancelFunction: { id in
            DispatchQueue(label: "cancel").asyncAfter(deadline: .now() + 2) {
                Task {
                    try await ssh.cancel(id: id);
                    await canceled.setCanceled(to: true);
                }
            }
        }

        
        let command = try await ssh.exec(command: "echo \"\(uuid)\" && sleep 30 && exit 10;", delegate: delegate);
        
        while (await canceled.canceled == false) {
            try await Task.sleep(nanoseconds: 10000);
        }
        
        XCTAssert(command.stdout == "\(uuid)\n")
        XCTAssertNotNil(command.exitSignal);
        XCTAssert(command.exitSignal! == "KILL");
    }
    
    func testMultipleCommandsInARow() async throws {
        guard let sshConfig = sshConfig else {
            throw TestErrors.CONFIG_IS_NIL
        }

        let ssh = SSH(options: sshConfig);
        
        for i in 0..<6 {
            let outputString = "Hello world!"
            
            let result = try await ssh.exec(command: "echo \"\(outputString)\"; exit \(i);");
            print(result);
            
            XCTAssert(result.exitCode == i, "Return code should be \(i)");
            
            XCTAssert(result.stdout == "\(outputString)\n", "Result stdout should match output");
        }
        
        await ssh.disconnect();
    }
    
    func testMultipleCommandsInARowParallel() async throws {
        
        guard let sshConfig = sshConfig else {
            throw TestErrors.CONFIG_IS_NIL
        }

        let ssh = SSH(options: sshConfig);
        
        await withThrowingTaskGroup(of: Void.self, returning: Void.self, body: { taskGroup in
            
            taskGroup.addTask {
                for _ in 0..<6 {
                    if self.connectionType! == "unraid" {
                        let result = try await ssh.exec(command: "cat /boot/config/ident.cfg");
                        print(result);
                    } else {
                        let result = try await ssh.exec(command: "ipconfig getifaddr en0");
                        print(result);
                    }
                }
            }
            
            taskGroup.addTask {
                for _ in 0..<6 {
                    if self.connectionType! == "unraid" {
                        let result = try await ssh.exec(command: "TERM=xterm top -1 -n 1 -b | grep '^%Cpu[[:digit:]+]' | tr '\\n' '|'");
                        print(result);
                    } else {
                        let result = try await ssh.exec(command: "top -l 1");
                        print(result);
                    }
                }
            }
            
            taskGroup.addTask {
                for _ in 0..<6 {
                    
                    let result = try await ssh.exec(command: "uptime");
                    print(result);
                }
            }
            
        })
        
        await ssh.disconnect();
    }
    
    func testDisconnectWithActiveCommand() async throws {
        guard let sshConfig = sshConfig else {
            throw TestErrors.CONFIG_IS_NIL
        }

        let ssh = SSH(options: sshConfig);
        
        let outputString1 = "Hello world!"
        let outputStderr1 = "Error world!"
        let exitCode1 = 15;
        let runCount1 = 5;

        await withThrowingTaskGroup(of: Void.self, returning: Void.self) { taskGroup in
            taskGroup.addTask {
                let result = try await ssh.exec(command: "for i in {1..\(runCount1)}; do echo \"\(outputString1)\"; echo \"\(outputStderr1)\" >&2; sleep 1; done; exit \(exitCode1);");
                print(result)
            }
            
            taskGroup.addTask {
                try await Task.sleep(nanoseconds: 2 * UInt64(pow(10.0, 9.0))); // wait 2s
                await ssh.disconnect();
            }
        }
        
        await ssh.disconnect();
    }
    
    func testAutoCloseStuckConnections() async throws {
        guard let sshConfig = sshConfig else {
            throw TestErrors.CONFIG_IS_NIL
        }

        let ssh = SSH(options: sshConfig);
        
        let outputString1 = "Hello world!"
        let outputStderr1 = "Error world!"
        let exitCode1 = 15;
        let runCount1 = 5;

        await withThrowingTaskGroup(of: Void.self, returning: Void.self) { taskGroup in
            for _ in 0..<11 {
                taskGroup.addTask {
                    let result = try await ssh.exec(command: "for i in {1..\(runCount1)}; do echo \"\(outputString1)\"; echo \"\(outputStderr1)\" >&2; sleep 1; done; exit \(exitCode1);");
                    print(result)
                }
            }
            
            
        }
        
        await ssh.disconnect();
    }
    
    #if !canImport(SwifterSwiftSSH_macos)
    
    func testRSAKey() throws {
        
        let keyPair = try generateRSAKeyPair();
        
        XCTAssert(keyPair.publicKey != "")
        XCTAssert(keyPair.privateKey != "")
    }
    
    #endif
}
