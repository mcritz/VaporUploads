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
        debugPrint("save file failed\n\t \(path)")
        throw FileError.couldNotSave
    }
}

struct FileUpload: Codable {
    var file: File
}

func routes(_ app: Application) throws {
    
    let logger = Logger(label: "routes")
    
    // MARK: static paths
    app.get { req in
        return "It works!"
    }

    app.get("hello") { req -> String in
        return "Hello, world!"
    }

    // MARK: /todos
    let todoController = TodoController()
    app.get("todos", use: todoController.index)
    app.get("todos", ":todoID", use: todoController.getOne)
    app.post("todos", use: todoController.create)
    app.delete("todos", ":todoID", use: todoController.delete)
    
    
    // MARK: /images
    let imageController = ImageController()
    app.get("images", use: imageController.index)
    
    /// Upload a file of up to 10MB
    app.on(.POST, "images", body: .collect(maxSize: 10_000_000)) { req -> EventLoopFuture<Image> in
        let image = try req.content.decode(Image.self)
        return image.save(on: req.db).map {
            do {
                try saveFile(name: image.id!.uuidString, data: image.data)
            } catch {
                let imageName = image.id?.uuidString ?? "unknown image"
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
            throw Abort(.internalServerError)
        }
        
        // Configure SwiftNIO to create a file stream.
        // Danger Zone! When we .openFile() we MUST later .close()
        let nbFileIO = NonBlockingFileIO(threadPool: app.threadPool)
        let fileHandle = nbFileIO.openFile(path: filePath, mode: .write, eventLoop: req.eventLoop)
        
        // Launch the stream…
        return fileHandle.map { fHand in
            // Here’s the tricky bit.
            // If we don’t organize our FileIO writes we end up in a race condition.
            // So, store the futures in an array so we can reason around their states.
            var futureFileIOWriters = [EventLoopFuture<()>]()
            
            // Vapor will now feed us bytes
            req.body.drain { someResult -> EventLoopFuture<Void> in
                switch someResult {
                case .buffer(let buffy):
                    // We have bytes. So, write them to disk in a future…
                    let wrote = nbFileIO.write(fileHandle: fHand,
                                               buffer: buffy,
                                               eventLoop: req.eventLoop)
                    // …adding the future to our array…
                    futureFileIOWriters.append(wrote)
                    // …and return for the next result
                    return req.eventLoop.future()
                    
                case .error(let err):
                    debugPrint("error", err)
                    do {
                        // Handle errors by closing and removing our file
                        try fHand.close()
                        try FileManager().removeItem(atPath: filePath)
                    } catch {
                        debugPrint("fail", error)
                    }
                    // Wail on fail
                    return req.eventLoop.makeFailedFuture(err)
                    
                case .end:
                    // Danger Zone!
                    // Bytes are done coming off the wire, but our FileIOWrites could still be happening.
                    // If we close the file handler now then bad things happen.
                    // Also, we have N number of Futures that haven’t given a result, yet.
                    // So, we need to collect the Futures and ensure their success.
                    // I’m using `.fold([EventLoopFuture<T>]` but there’s probably other ways of doing this.
                    return req.eventLoop.future().fold(futureFileIOWriters) { _, _ in
                        // return success…
                        return req.eventLoop.makeSucceededFuture(())
                    }.always { _ in
                        // and when we’re done with all the file writes, we MUST close the file.
                        try? fHand.close()
                    }
                }
            }
        }.map { _ in
            return HTTPStatus.accepted // 202: accepted for processing
        }
    }
}
