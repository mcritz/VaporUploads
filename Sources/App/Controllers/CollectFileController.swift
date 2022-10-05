//
//  File.swift
//  
//
//  Created by Michael Critz on 4/13/20.
//

import Fluent
import Vapor

struct CollectFileController {
    let logger = Logger(label: "imagecontroller")
    
    func index(req: Request) async throws -> [CollectModel] {
        return try await CollectModel.query(on: req.db).all()
    }
    
    func upload(req: Request) async throws -> HTTPStatus {
        let image = try req.content.decode(CollectModel.self)
        try await image.save(on: req.db)
        let imageName = image.id?.uuidString ?? "unknown image"
        do {
            try self.saveFile(name: imageName, data: image.data)
            return HTTPStatus.ok
        } catch {
            logger.critical("failed to save file \(error.localizedDescription)")
            return HTTPStatus.internalServerError
        }
    }
}

extension CollectFileController {
    fileprivate func saveFile(name: String, data: Data) throws {
        let path = FileManager.default
            .currentDirectoryPath.appending("/\(name)")
        if FileManager.default.createFile(atPath: path,
                                          contents: data,
                                          attributes: nil) {
            logger.info("saved file\n\t \(path)")
        } else {
            logger.critical("failed to save file for image \(name)")
            throw FileError.couldNotSave(reason: "error writing file \(path)")
        }
    }
}

enum FileError: Error {
    case couldNotSave(reason: String)
}
