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

func routes(_ app: Application) throws {
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
    
    app.on(.POST, "images", body: .collect(maxSize: 10_000_000)) { req -> EventLoopFuture<Image> in
        guard let buffer = req.body.data else {
            throw Abort(.badRequest)
        }
        let image = try FormDataDecoder().decode(Image.self,
                                                 from: buffer,
                                                 headers: req.headers)
        try saveFile(name: image.id!.uuidString, data: image.data)
        return image.save(on: req.db).map {
            return image
        }
    }

}
