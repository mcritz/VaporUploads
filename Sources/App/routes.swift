import Fluent
import Vapor

enum FileError: Error {
    case couldNotSave
}

fileprivate func saveFile(name: String, data: Data) throws {
    let path = FileManager.default
        .currentDirectoryPath.appending("/\(name)")
    if FileManager.default.createFile(atPath: path,
                                      contents: data,
                                      attributes: nil) {
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
    
    let uploadController = UploadController()
    app.on(.GET, "files", use: uploadController.index)
    app.on(.GET, "files", ":fileID", use: uploadController.getOne)
    app.on(.GET, "files", ":fileID", "download", use: uploadController.downloadOne)
    app.on(.POST,
           "files",
           body: .stream,
           use: uploadController.upload)
}
