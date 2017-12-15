//
//  AppDelegate.swift
//  Foreground App
//
//  Created by Ben Leggiero on 2017-12-15.
//  Copyright © 2017 Ben Leggiero. All rights reserved.
//

import Cocoa
import SocketIpcSharedLibrary



@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet var textArea: NSTextView!
    
    let client: ClientProtocol = SscceClient()
    

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


    @IBAction func didPressSendButton(_ sender: NSButton) {
        
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(50505).bigEndian
        address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        
        do {
            try client.send(data: textArea.string.data(using: .utf8)!, to: &address) { result in
                switch result {
                case .some(let value):
                    print("Got value back from server:", value)
                    
                case .none(let error):
                    print("Got error:", error)
                }
            }
        }
        catch let error {
            print("Failed to send data to server:", error)
        }
    }
}

