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

extension HTTPHeaders {
    static let fileName = Name("File-Name")
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
    
    func fileExtension(for headers: HTTPHeaders) -> String {
        // Parse the header’s Content-Type to determine the file extension
        var fileExtension = "tmp"
        if let contentType = headers.contentType {
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
        return fileExtension
    }
    
    func filename(with headers: HTTPHeaders) -> String {
        let fileNameHeader = headers["File-Name"]
        if let inferredName = fileNameHeader.first {
            return inferredName
        }
        let fileExt = fileExtension(for: headers)
        return "upload-\(UUID().uuidString).\(fileExt)"
    }
    
    /// Upload huge files (100s of gigs, even)
    /// Problem 1: If we don’t handle the body as a stream, we’ll end up loading the enire file into memory.
    /// Problem 2: Needs to scale for hunderds or thousands of concurrent transfers.
    /// Solution: stream the incoming bytes to a file on the server.
    /**
     * Example:
        curl --location --request POST 'localhost:8080/bigfile' \
            --header 'Content-Type: video/mp4' \
            --data-binary '@/Users/USERNAME/path/to/GiganticMultiGigabyteFile.mp4'
     */
    app.on(.POST, "bigfile", body: .stream) { req -> EventLoopFuture<HTTPStatus> in
        let statusPromise = req.eventLoop.makePromise(of: HTTPStatus.self)
        
        // Create a file on disk
        let filePath = app.directory.workingDirectory + "Uploads/" + filename(with: req.headers)
        guard FileManager.default.createFile(atPath: filePath,
                                       contents: nil,
                                       attributes: nil) else {
            logger.critical("Could not upload \(filePath)")
            throw Abort(.internalServerError)
        }
        
        // Configure SwiftNIO to create a file stream.
        let nbFileIO = NonBlockingFileIO(threadPool: app.threadPool)
        let fileHandle = nbFileIO.openFile(path: filePath, mode: .write, eventLoop: req.eventLoop)
        
        // Launch the stream…
        return fileHandle.map { fHand in
            // Vapor will now feed us bytes
            req.body.drain { someResult -> EventLoopFuture<Void> in
                let drainPromise = req.eventLoop.makePromise(of: Void.self)
                
                switch someResult {
                case .buffer(let buffy):
                    // We have bytes. So, write them to disk, and handle our promise
                    _ = nbFileIO.write(fileHandle: fHand,
                                   buffer: buffy,
                                   eventLoop: req.eventLoop)
                        .always { outcome in
                            switch outcome {
                            case .success(let yep):
                                drainPromise.succeed(yep)
                            case .failure(let err):
                                drainPromise.fail(err)
                            }
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
