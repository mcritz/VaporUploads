import Fluent
import FluentSQLiteDriver
import Vapor

// configures your application
public func configure(_ app: Application) throws {
    let logger = Logger(label: "configure")
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)

    app.migrations.add(CreateUpload())
    
    try app.autoMigrate().wait()
    
    let configuredDir = configureUploadDirectory(for: app)
    configuredDir.whenFailure { err in
        logger.error("Could not create uploads directory \(err.localizedDescription)")
    }
    configuredDir.whenSuccess { dirPath in
        logger.info("created upload directory at \(dirPath)")
    }

    // register routes
    try routes(app)
}
