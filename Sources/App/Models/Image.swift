//
//  File.swift
//  
//
//  Created by Michael Critz on 4/13/20.
//

import Fluent
import Vapor

final class Image: Model, Content {
    init() { }
    
    static let schema = "images"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "data")
    var data: Data
    
    init(id: UUID? = nil, data: Data) {
        self.id = id
        self.data = data
    }
}
