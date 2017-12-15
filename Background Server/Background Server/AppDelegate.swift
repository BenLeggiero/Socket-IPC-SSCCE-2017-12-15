//
//  AppDelegate.swift
//  Background Server
//
//  Created by Ben Leggiero on 2017-12-15.
//  Copyright © 2017 Ben Leggiero. All rights reserved.
//

import Cocoa
import SocketIpcSharedLibrary



@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var outputTextPane: NSTextView!
    
    private var server: ServerProtocol!
    
    
    override init() {
        super.init()
        server = generateServer()
    }
    

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        do {
            try server.start()
        }
        catch let error {
            print("Error when starting server:", error)
        }
    }

    
    func applicationWillTerminate(_ aNotification: Notification) {
        server.stop()
    }
    
    
    func generateServer() -> SscceServer {
        
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET);
        address.sin_port = in_port_t(50505).bigEndian;
        address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian;
        
        return SscceServer.init(address: address,
                                clientRequestHandler: requestHandler,
                                clientResponseHandler: responseHandler)
    }
    
    
    func requestHandler(request: DescriptiveOptional<Data>) {
        switch request {
        case .some(let value):
            let stringValue = String(data: value, encoding: .utf8)!
            print("Got request:", stringValue)
            outputTextPane.string = stringValue
            
        case .none(let error):
            print("Got error:", error)
        }
    }
    
    
    func responseHandler() -> Data? {
        return "Ahoy, client!".data(using: .utf8)!
    }
}

