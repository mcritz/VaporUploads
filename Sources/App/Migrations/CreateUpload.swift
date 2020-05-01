import Fluent

struct CreateUpload: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(Upload.schema)
            .id()
            .field("fileName", .string, .required)
            .create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(Upload.schema).delete()
    }
}
