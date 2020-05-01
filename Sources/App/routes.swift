import Fluent
import Vapor

enum FileError: Error {
    case couldNotSave
}

fileprivate func saveFile(name: String, data: Data) throws {
    let path = FileManager.default.currentDirectoryPath.appending("/\(name)")
    if FileManager.default.createFile(atPath: path, contents: data, attributes: nil) {
        debugPrint("saved file\n\t \(path)")
    } else {
        throw FileError.couldNotSave
    }
}

func routes(_ app: Application) throws {
    
    let logger = Logger(label: "routes")
    
    // MARK: /images
    let imageController = ImageController()
    app.get("images", use: imageController.index)
    
    /// Upload a file of up to 10MB
    app.on(.POST, "images", body: .collect(maxSize: 10_000_000)) { req -> EventLoopFuture<Image> in
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
    
    /// Upload a huge file (100s of gigs, even)
    /// Problem: If we don’t handle the body as a stream, we’ll end up loading the enire file into memory.
    /// Solution: stream the incoming bytes to a file on the server.
    /**
     * Example:
        curl --location --request POST 'localhost:8080/bigfile' \
            --header 'Content-Type: video/mp4' \
            --data-binary '@/Users/USERNAME/path/to/GiganticMultiGigabyteFile.mp4'
     */
    app.on(.POST, "bigfile", body: .stream) { req -> EventLoopFuture<HTTPStatus> in
        let statusPromise = req.eventLoop.makePromise(of: HTTPStatus.self)
        
        // Parse the header’s Content-Type to determine the file extension
        var fileExtension = "tmp"
        if let contentType = req.headers.contentType {
            switch contentType {
            case .jpeg:
                fileExtension = "jpg"
            case .mp3:
                fileExtension = "mp3"
            case .init(type: "video", subType: "mp4"):
                fileExtension = "mp4"
            default:
                fileExtension = "tmp"
            }
        }
        
        // Create a file on disk
        let filePath = app.directory.workingDirectory + "upload-\(UUID().uuidString).\(fileExtension)"
        guard FileManager().createFile(atPath: filePath,
                                       contents: nil,
                                       attributes: nil) else {
            logger.critical("Could not upload \(filePath)")
            throw Abort(.internalServerError)
        }
        
        // Configure SwiftNIO to create a file stream.
        // Danger Zone! When we .openFile() we MUST later .close()
        let nbFileIO = NonBlockingFileIO(threadPool: app.threadPool)
        let fileHandle = nbFileIO.openFile(path: filePath, mode: .write, eventLoop: req.eventLoop)
        
        // Launch the stream…
        return fileHandle.map { fHand in
            // Vapor will now feed us bytes
            req.body.drain { someResult -> EventLoopFuture<Void> in
                let drainPromise = req.eventLoop.makePromise(of: Void.self)
                
                switch someResult {
                case .buffer(let buffy):
                    // We have bytes. So, write them to disk, and succeed our promise
                    nbFileIO.write(fileHandle: fHand,
                                               buffer: buffy,
                                               eventLoop: req.eventLoop)
                        .always { _ in
                            drainPromise.succeed(())
                    }
                case .error(let err):
                    statusPromise.succeed(.internalServerError)
                    do {
                        // Handle errors by closing and removing our file
                        try fHand.close()
                        try FileManager.default.removeItem(atPath: filePath)
                    } catch {
                        debugPrint("catastrophic failure", error)
                    }
                    // Inform the client
                    statusPromise.succeed(.internalServerError)
                    
                case .end:
                    statusPromise.succeed(.ok)
                    drainPromise.succeed(())
                }
                return drainPromise.futureResult
            }
        }.transform(to: statusPromise.futureResult)
    }
}
