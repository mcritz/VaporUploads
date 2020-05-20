//
//  File.swift
//  
//
//  Created by Michael Critz on 5/13/20.
//

import Fluent
import Vapor

final class WebSocketController {
    let logger = Logger(label: "WebSocketController")
    
    func upload(req: Request, ws: WebSocket) -> () {
        ws.onText { (ws, string) in
            ws.send("Server got \(string)")
        }
    }
}
