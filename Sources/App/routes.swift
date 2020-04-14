import Fluent
import Vapor

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
}
