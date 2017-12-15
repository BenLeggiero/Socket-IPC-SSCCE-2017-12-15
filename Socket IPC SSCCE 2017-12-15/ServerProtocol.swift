//
//  ServerProtocol.swift
//  Shared Library
//
//  Created by Ben Leggiero on 2017-12-15.
//  Copyright © 2017 Ben Leggiero. All rights reserved.
//

import Foundation



public protocol ServerProtocol {
    
    func start() throws
    
    func stop()
}
