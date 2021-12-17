//
//  swifter_swift_ssh.swift
//  swifter-swift-ssh
//
//  Created by Nils Bergmann on 17.12.21.
//

public class SSH {

    private let session: ssh_session?;
    private var ssh_connected: Bool = false;
    
    init(options: SSHOption) {
        self.session = ssh_new();
        
        var port = options.port;
        
        if self.session != nil {
            ssh_options_set(self.session, SSH_OPTIONS_HOST, options.host);
            ssh_options_set(self.session, SSH_OPTIONS_PORT, &port);
        }
    }
    
    public func connect() {
        
    }
    
    deinit {
        if self.session != nil {
            ssh_free(self.session);
        }
    }
}
