//
//  File.swift
//  
//
//  Created by Michael Critz on 4/13/20.
//

import Fluent

struct CreateImage: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(Image.schema)
            .id()
            .field("data", .data, .required)
            .create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(Image.schema).delete()
    }
}
