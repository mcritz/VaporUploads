import Fluent
import Vapor
import NIOCore

struct StreamController {
    let logger = Logger(label: "StreamController")
    
    func index(req: Request) async throws -> [StreamModel] {
        try await StreamModel.query(on: req.db).all()
    }
    
    func getOne(req: Request) async throws -> StreamModel {
        guard let model = try await StreamModel.find(req.parameters.get("fileID"), on: req.db) else {
            throw Abort(.badRequest)
        }
        return model
    }
    
    /// Streaming download comes with Vapor “out of the box”.
    /// Call `req.fileio.streamFile` with a path and Vapor will generate a suitable Response.
    func downloadOne(req: Request) async throws -> Response {
        let upload = try await getOne(req: req)
        return req.fileio.streamFile(at: upload.filePath(for: req.application))
    }
    
    // MARK: The interesting bit
    /// Upload huge files (100s of gigs, even)
    /// - Problem 1: If we don’t handle the body as a stream, we’ll end up loading the entire file into memory on request.
    /// - Problem 2: Needs to scale for hundreds or thousands of concurrent transfers. So, proper memory management is crucial.
    /// - Problem 3: When *streaming* a file over HTTP (as opposed to encoding with multipart form) we need a way to know what the user’s desired filename is. So we handle a custom Header.
    /// - Problem 4: Custom headers are sometimes filtered out of network requests, so we need a fallback naming for files.
    /**
     * Example:
        curl --location --request POST 'localhost:8080/fileuploadpath' \
            --header 'Content-Type: video/mp4' \
            --header 'File-Name: bunnies-eating-strawberries.mp4' \
            --data-binary '@/Users/USERNAME/path/to/GiganticMultiGigabyteFile.mp4'
     */
    func upload(req: Request) async throws -> some AsyncResponseEncodable {
        let logger = Logger(label: "StreamController.upload")
        // Create a file on disk based on our `Upload` model.
        let fileName = filename(with: req.headers)
        let upload = StreamModel(fileName: fileName)
        let filePath = upload.filePath(for: req.application)
        
        // Remove any file with the same name
        try? FileManager.default.removeItem(atPath: filePath)
        guard FileManager.default.createFile(atPath: filePath,
                                       contents: nil,
                                       attributes: nil) else {
            logger.critical("Could not upload \(upload.fileName)")
            throw Abort(.internalServerError)
        }
        let nioFileHandle = try NIOFileHandle(path: filePath, mode: .write)
        defer {
            do {
                try nioFileHandle.close()
            } catch {
                logger.error("\(error.localizedDescription)")
            }
        }
        do {
            var offset: Int64 = 0
            for try await byteBuffer in req.body {
                do {
                    try await req.application.fileio.write(fileHandle: nioFileHandle,
                                                           toOffset: offset,
                                                           buffer: byteBuffer,
                                                           eventLoop: req.eventLoop).get()
                    offset += Int64(byteBuffer.readableBytes)
                } catch {
                    logger.error("\(error.localizedDescription)")
                }
            }
            try await upload.save(on: req.db)
        } catch {
            try FileManager.default.removeItem(atPath: filePath)
            logger.error("File save failed for \(filePath)")
            throw Abort(.internalServerError)
        }
        logger.info("saved \(upload)")
        return "Saved \(upload)"
    }
}
