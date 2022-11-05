import Fluent
import Vapor

final class StreamModel: Model, Content, CustomStringConvertible {
    init() { }
    
    static let schema = "stream"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "fileName")
    var fileName: String
    
    public func filePath(for app: Application) -> String {
        app.directory.workingDirectory + "Uploads/" + fileName
    }
    
    var description: String {
        return fileName
    }
    
    init(id: UUID? = nil, fileName: String) {
        self.id = id
        self.fileName = fileName
    }
}
