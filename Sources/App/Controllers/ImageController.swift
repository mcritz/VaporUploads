//
//  File.swift
//  
//
//  Created by Michael Critz on 4/13/20.
//

import Fluent
import Vapor
import NIO

struct ImageController {
    func index(req: Request) throws -> EventLoopFuture<[Image]> {
        return Image.query(on: req.db).all()
    }
}
