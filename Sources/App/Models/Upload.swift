import Fluent
import Vapor

final class Upload: Model, Content {
    init() { }
    
    static let schema = "uploads"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "fileName")
    var fileName: String
    
    public func filePath(for app: Application) -> String {
        app.directory.workingDirectory + "Uploads/" + fileName
    }
    
    init(id: UUID? = nil, fileName: String) {
        self.id = id
        self.fileName = fileName
    }
}
