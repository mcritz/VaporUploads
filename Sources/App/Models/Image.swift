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
    
    @Field(key: "path")
    var path: String
    
    @Field(key: "filename")
    var filename: String
    
    init(id: UUID? = nil, path: String, filename: String) {
        self.id = id
        self.path = path
        self.filename = filename
    }
}
