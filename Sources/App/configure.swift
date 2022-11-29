import Fluent
import FluentPostgresDriver
import Vapor

// configures your application
public func configure(_ app: Application) throws {
    let logger = Logger(label: "configure")
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    let port = Environment.get("PORT").flatMap(Int.init)
    let dbHost = Environment.get("DATABASE_HOST") ?? "localhost"
    let dbDatabase = Environment.get("DATABASE_NAME") ?? "db"
    let dbUser = Environment.get("DATABASE_USERNAME") ?? ""
    
    app.http.server.configuration.port = port ?? 8080
     
    let dbPassword = Environment.get("DATABASE_PASSWORD") ?? ""
    
    app.databases.use(.postgres(hostname: dbHost,
                                username: dbUser,
                                password: dbPassword,
                                database: dbDatabase),
                      as: .psql)

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
