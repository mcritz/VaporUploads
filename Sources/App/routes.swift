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
    
    /// Using `body: .collect` we can load the request into memory.
    /// This is easier than streaming at the expense of using much more system memory.
    app.on(.POST, "images",
           body: .collect(maxSize: 10_000_000),
           use: imageController.upload)
    
    // MARK: /files
    let uploadController = UploadController()
    /// using `body: .stream` we can get chunks of data from the client, keeping memory use low.
    app.on(.POST, "files",
        body: .stream,
        use: uploadController.upload)
    app.on(.GET, "files", use: uploadController.index)
    app.on(.GET, "files", ":fileID", use: uploadController.getOne)
    app.on(.GET, "files", ":fileID", "download", use: uploadController.downloadOne)
}
