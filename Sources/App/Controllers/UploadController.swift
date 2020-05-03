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
    
    
    
    /// Upload huge files (100s of gigs, even)
    /// Problem 1: If we don’t handle the body as a stream, we’ll end up loading the enire file into memory.
    /// Problem 2: Needs to scale for hunderds or thousands of concurrent transfers.
    /// Solution: stream the incoming bytes to a file on the server.
    /**
     * Example:
        curl --location --request POST 'localhost:8080/fileuploadpath' \
            --header 'Content-Type: video/mp4' \
            --data-binary '@/Users/USERNAME/path/to/GiganticMultiGigabyteFile.mp4'
     */
    func upload(req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let statusPromise = req.eventLoop.makePromise(of: HTTPStatus.self)
        
        // Create a file on disks
        let fileName = filename(with: req.headers)
        let filePath = req.application.directory.workingDirectory + "Uploads/" + fileName
        guard FileManager.default.createFile(atPath: filePath,
                                       contents: nil,
                                       attributes: nil) else {
            Logger(label: "science.pixel.fileuploader")
                    .critical("Could not upload \(filePath)")
            throw Abort(.internalServerError)
        }
        
        // Configure SwiftNIO to create a file stream.
        let nbFileIO = NonBlockingFileIO(threadPool: req.application.threadPool)
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
                    do {
                        // Handle errors by closing and removing our file
                        try? fHand.close()
                        try FileManager.default.removeItem(atPath: filePath)
                    } catch {
                        debugPrint("catastrophic failure on \(err)", error)
                    }
                    // Inform the client
                    statusPromise.succeed(.internalServerError)
                    
                case .end:
                    statusPromise.succeed(.ok)
                    drainPromise.succeed(())
                    _ = Upload(fileName: fileName).save(on: req.db)
                }
                return drainPromise.futureResult
            }
        }.transform(to: statusPromise.futureResult)
    }
    
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
