import Fluent
import FluentSQLiteDriver
import Vapor

// configures your application
public func configure(_ app: Application) throws {
    let logger = Logger(label: "configure")
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    if let port = Environment.get("PORT").flatMap(Int.init) {
        app.http.server.configuration.port = port
    }


    app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)

    app.migrations.add(CreateCollect())
    app.migrations.add(CreateStream())
    
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
