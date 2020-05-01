import Fluent
import FluentSQLiteDriver
import Vapor

// configures your application
public func configure(_ app: Application) throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)

    app.migrations.add(CreateTodo())
    app.migrations.add(CreateImage())
    app.migrations.add(CreateUpload())
    
    try app.autoMigrate().wait()
    
    let configuredDir = configureUploadDirectory(for: app)
    configuredDir.whenFailure { err in
        Logger(label: "codes.uploads.directory-config")
            .error("Could not create uploads directory \(err.localizedDescription)")
    }
    configuredDir.whenSuccess { dirPath in
        Logger(label: "codes.uploads.directory-config")
            .info("created upload directory at \(dirPath)")
    }

    // register routes
    try routes(app)
}

fileprivate func configureUploadDirectory(named directoryName: String = "Uploads/", for app: Application) -> EventLoopFuture<String> {
    let createdDirectory = app.eventLoopGroup.next().makePromise(of: String.self)
    var uploadDirectoryName = app.directory.workingDirectory
    if directoryName.last != "/" {
        uploadDirectoryName += "/"
    }
    uploadDirectoryName += directoryName
    do {
        try FileManager.default.createDirectory(atPath: uploadDirectoryName,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
        createdDirectory.succeed(uploadDirectoryName)
    } catch {
        createdDirectory.fail(FileError.couldNotSave)
    }
    return createdDirectory.futureResult
}
