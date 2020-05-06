//
//  File.swift
//  
//
//  Created by Michael Critz on 4/13/20.
//

import Fluent
import Vapor

struct ImageController {
    func index(req: Request) throws -> EventLoopFuture<[Image]> {
        return Image.query(on: req.db).all()
    }
    
    func upload(req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let image = try req.content.decode(Image.self)
        return image.save(on: req.db).map {
            let imageName = image.id?.uuidString ?? "unknown image"
            do {
                try saveFile(name: imageName, data: image.data)
            } catch {
                logger.critical("failed to save file for image \(imageName)")
            }
            return image
        }
    }
}
