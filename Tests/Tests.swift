//
//  Tests.swift
//  Tests
//
//  Created by Nils Bergmann on 19/12/2021.
//

import XCTest
@testable import SwifterSwiftSSH_macos

class Tests: XCTestCase {
    
    var sshConfig: SSHOption?;
        
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
        let port = credentialsDictionary["port"] as? Int ?? 22;
        
        self.sshConfig = SSHOption(host: host, port: port, username: username, password: password);
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
        
        XCTAssert(result.exitCode == 15, "Return code should be 0");
        
        XCTAssert(result.stdout == "\(outputString)\n", "Result stdout should match output");
        
        await ssh.disconnect();
    }
    
    func testParallelExecution() async throws {
        guard let sshConfig = sshConfig else {
            throw TestErrors.CONFIG_IS_NIL
        }

        let ssh = SSH(options: sshConfig);
        
//        try await ssh.exec(command: "ls -lah");
        
        // Command 1
        
        let outputString1 = "Hello world!"
        let outputStderr1 = "Error world!"
        let exitCode1 = 15;
        let runCount1 = 5;

        async let command1 = ssh.exec(command: "for i in {1..\(runCount1)}; do echo \"\(outputString1)\"; echo \"\(outputStderr1)\" >&2; sleep 1; done; exit \(exitCode1);");
        
//        try await ssh.exec(command: "for i in {1..\(runCount1)}; do echo \"\(outputString1)\"; echo \"\(outputStderr1)\" >&2; sleep 1; done; exit \(exitCode1);")
        

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
    
}
