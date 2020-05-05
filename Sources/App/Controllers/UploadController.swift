import Fluent
import Vapor

struct UploadController {
    
    func index(req: Request) throws -> EventLoopFuture<[Upload]> {
        Upload.query(on: req.db).all()
    }
    
    func getOne(req: Request) throws -> EventLoopFuture<Upload> {
        Upload.find(req.parameters.get("fileID"), on: req.db)
            .unwrap(or: Abort(.notFound))
    }
    
    /// Streaming download comes with Vapor “out of the box”.
    /// Call `req.fileio.streamFile` with a path and Vapor will generate a suitable Response.
    func downloadOne(req: Request) throws -> EventLoopFuture<Response> {
        try getOne(req: req).map { upload -> Response in
            req.fileio.streamFile(at: upload.filePath(for: req.application))
        }
    }
    
    /// Upload huge files (100s of gigs, even)
    /// - Problem 1: If we don’t handle the body as a stream, we’ll end up loading the enire file into memory.
    /// - Problem 2: Needs to scale for hunderds or thousands of concurrent transfers.
    /// - Problem 3: When *streaming* a file over HTTP (as opposed to encoding with multipart form) we need a way to know what the user’s desired filename is. So we handle a custom Header.
    /// - Problem 4: Custom headers are sometimes filtered out of network requests, so we need a fallback naming for files.
    /**
     * Example:
        curl --location --request POST 'localhost:8080/fileuploadpath' \
            --header 'Content-Type: video/mp4' \
            --header 'File-Name: bunnies.jpg' \
            --data-binary '@/Users/USERNAME/path/to/GiganticMultiGigabyteFile.mp4'
     */
    func upload(req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let loggger = Logger(label: "UploadController.upload")
        let statusPromise = req.eventLoop.makePromise(of: HTTPStatus.self)
        
        // Create a file on disk based on our `Upload` model.
        let fileName = filename(with: req.headers)
        let upload = Upload(fileName: fileName)
        guard FileManager.default.createFile(atPath: upload.filePath(for: req.application),
                                       contents: nil,
                                       attributes: nil) else {
            logger.critical("Could not upload \(upload.fileName)")
            throw Abort(.internalServerError)
        }
        
        // Configure SwiftNIO to create a file stream.
        let nbFileIO = NonBlockingFileIO(threadPool: req.application.threadPool) // Should move out of this func, but left it here for ease of understanding.
        let fileHandle = nbFileIO.openFile(path: upload.filePath(for: req.application),
                                           mode: .write,
                                           eventLoop: req.eventLoop)
        
        // Launch the stream…
        return fileHandle.map { fHand in
            // Vapor request will now feed us bytes
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
                    do {
                        // Handle errors by closing and removing our file
                        try? fHand.close()
                        try FileManager.default.removeItem(atPath: upload.filePath(for: req.application))
                    } catch {
                        debugPrint("catastrophic failure on \(err)", error)
                    }
                    // Inform the client
                    statusPromise.succeed(.internalServerError)
                    
                case .end:
                    drainPromise.succeed(())
                    _ = upload
                        .save(on: req.db)
                        .map { _ in
                        statusPromise.succeed(.ok)
                    }
                }
                return drainPromise.futureResult
            }
        }.transform(to: statusPromise.futureResult)
    }
}

// Helpers for naming files
extension UploadController {
    private func fileExtension(for headers: HTTPHeaders) -> String {
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
                fileExtension = "bits"
            }
        }
        return fileExtension
    }
    
    private func filename(with headers: HTTPHeaders) -> String {
        let fileNameHeader = headers["File-Name"]
        if let inferredName = fileNameHeader.first {
            return inferredName
        }
        
        let fileExt = fileExtension(for: headers)
        return "upload-\(UUID().uuidString).\(fileExt)"
    }
}

// Helpers for `configure.swift`
extension UploadController {
    /// Creates the upload directory as part of the working directory
    /// - Parameters:
    ///   - directoryName: sub-directory name
    ///   - app: Application
    /// - Returns: name of the directory
    static public func configureUploadDirectory(named directoryName: String = "Uploads/", for app: Application) -> EventLoopFuture<String> {
        let createdDirectory = app.eventLoopGroup.next().makePromise(of: String.self)
        var uploadDirectoryName = app.directory.workingDirectory
        if directoryName.last != "/" {
            uploadDirectoryName += "/"
        }
        uploadDirectoryName += directoryName
        do {
            try FileManager.default.createDirectory(atPath: uploadDirectoryName,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
            createdDirectory.succeed(uploadDirectoryName)
        } catch {
            createdDirectory.fail(FileError.couldNotSave)
        }
        return createdDirectory.futureResult
    }
}
