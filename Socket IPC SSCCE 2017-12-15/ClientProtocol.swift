//
//  ClientProtocol.swift
//  Shared Library
//
//  Created by Ben Leggiero on 2017-12-15.
//  Copyright © 2017 Ben Leggiero. All rights reserved.
//

import Foundation



public protocol ClientProtocol {
    
    typealias ServerResponseHandler = (_ response: DescriptiveOptional<Data>) -> Void
    
    
    func send(data: Data, to address: inout sockaddr_in, andReceive responseHandler: @escaping ServerResponseHandler) throws
}
