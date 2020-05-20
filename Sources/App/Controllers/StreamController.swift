import Fluent
import Vapor

struct StreamController {
    let logger = Logger(label: "StreamController")
    
    func index(req: Request) throws -> EventLoopFuture<[StreamModel]> {
        StreamModel.query(on: req.db).all()
    }
    
    func getOne(req: Request) throws -> EventLoopFuture<StreamModel> {
        StreamModel.find(req.parameters.get("fileID"), on: req.db)
            .unwrap(or: Abort(.notFound))
    }
    
    /// Streaming download comes with Vapor “out of the box”.
    /// Call `req.fileio.streamFile` with a path and Vapor will generate a suitable Response.
    func downloadOne(req: Request) throws -> EventLoopFuture<Response> {
        try getOne(req: req).map { upload -> Response in
            req.fileio.streamFile(at: upload.filePath(for: req.application))
        }
    }
    
    // MARK: The interesting bit
    /// Upload huge files (100s of gigs, even)
    /// - Problem 1: If we don’t handle the body as a stream, we’ll end up loading the entire file into memory on request.
    /// - Problem 2: Needs to scale for hunderds or thousands of concurrent transfers. So, proper memory management is crucial.
    /// - Problem 3: When *streaming* a file over HTTP (as opposed to encoding with multipart form) we need a way to know what the user’s desired filename is. So we handle a custom Header.
    /// - Problem 4: Custom headers are sometimes filtered out of network requests, so we need a fallback naming for files.
    /**
     * Example:
        curl --location --request POST 'localhost:8080/fileuploadpath' \
            --header 'Content-Type: video/mp4' \
            --header 'File-Name: bunnies-eating-strawberries.mp4' \
            --data-binary '@/Users/USERNAME/path/to/GiganticMultiGigabyteFile.mp4'
     */
    func upload(req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let logger = Logger(label: "StreamController.upload")
        let statusPromise = req.eventLoop.makePromise(of: HTTPStatus.self)
        
        // Create a file on disk based on our `Upload` model.
        let fileName = filename(with: req.headers)
        let upload = StreamModel(fileName: fileName)
        guard FileManager.default.createFile(atPath: upload.filePath(for: req.application),
                                       contents: nil,
                                       attributes: nil) else {
            logger.critical("Could not upload \(upload.fileName)")
            throw Abort(.internalServerError)
        }
        
        // Configure SwiftNIO to create a file stream.
        let nbFileIO = req.application.fileio
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
                case .error(let errz):
                    do {
                        drainPromise.fail(errz)
                        // Handle errors by closing and removing our file
                        try? fHand.close()
                        try FileManager.default.removeItem(atPath: upload.filePath(for: req.application))
                    } catch {
                        debugPrint("catastrophic failure on \(errz)", error)
                    }
                    // Inform the client
                    statusPromise.succeed(.internalServerError)
                    
                case .end:
//                    do {
//                        try fHand.close()
//                    } catch {
//                        debugPrint("failed to close fHand", error)
//                    }
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
