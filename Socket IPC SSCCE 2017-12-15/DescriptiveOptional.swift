//
//  DescriptiveOptional.swift
//  Shared Library
//
//  Created by Ben Leggiero on 2017-12-18.
//  Copyright © 2017 Ben Leggiero. All rights reserved.
//

import Foundation



public enum DescriptiveOptional<Value> {
    
    /// There is some value.
    /// The associated value is that value.
    case some(Value)
    
    /// There is no value.
    /// The associated value is the error that describes why there is no value
    case none(Error)
}
