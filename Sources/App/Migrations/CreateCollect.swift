import Fluent

struct CreateCollect: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(CollectModel.schema)
            .id()
            .field("data", .data, .required)
            .create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(CollectModel.schema).delete()
    }
}
