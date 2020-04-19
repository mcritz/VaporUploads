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
    
    func upload(req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let nbFileIO = NonBlockingFileIO(threadPool: NIOThreadPool(numberOfThreads: 2))
        let workPath = DirectoryConfiguration.detect().workingDirectory
        let name = "upload-\(UUID()).tmp"
        let writePath = workPath + name
        let thisFileManager = FileManager()
        thisFileManager.createFile(atPath: writePath,
                                   contents: nil,
                                   attributes: nil)
        let futureFile = nbFileIO.openFile(path: writePath, eventLoop: req.eventLoop)
        let uploadFileHandle = try NIOFileHandle(path: writePath, mode: .write, flags: .allowFileCreation())
        let result = futureFile.map { fileHandler, fileRegion in
            
            req.body.drain { streamResult -> EventLoopFuture<Void> in
                switch streamResult {
                case .buffer(let buffy):
                    return nbFileIO.write(fileHandle: fileHandler, buffer: buffy, eventLoop: req.eventLoop)
                case .error:
                    try? fileHandler.close()
                    try? thisFileManager.removeItem(atPath: writePath)
                    return req.eventLoop.makeFailedFuture(FileError.couldNotSave).map {
                        HTTPStatus.internalServerError
                    }
                case .end:
                    try? fileHandler.close()
                    return req.eventLoop.makeSucceededFuture(()).map {
                        HTTPStatus.created
                    }
                }
            }
        }
        return result.map { _ in
            HTTPStatus.accepted
        }
    }
}
