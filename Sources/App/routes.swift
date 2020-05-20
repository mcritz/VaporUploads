import Fluent
import Vapor

func routes(_ app: Application) throws {
    // MARK: /collect
    let collectFileController = CollectFileController()
    app.get("collect", use: collectFileController.index)
    
    /// Using `body: .collect` we can load the request into memory.
    /// This is easier than streaming at the expense of using much more system memory.
    app.on(.POST, "collect",
           body: .collect(maxSize: 10_000_000),
           use: collectFileController.upload)
    
    // MARK: /stream
    let uploadController = StreamController()
    /// using `body: .stream` we can get chunks of data from the client, keeping memory use low.
    app.on(.POST, "stream",
        body: .stream,
        use: uploadController.upload)
    app.on(.GET, "stream", use: uploadController.index)
    app.on(.GET, "stream", ":fileID", use: uploadController.getOne)
    app.on(.GET, "stream", ":fileID", "download", use: uploadController.downloadOne)
    
    // MARK: /websocket
    let webSocketController = WebSocketController()
    app.webSocket("websocket", onUpgrade: webSocketController.upload)
}
