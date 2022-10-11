//
//  Request+AsyncBytes.swift
//  
//
//  Created by Michael Critz on 10/9/22.
//

import AsyncAlgorithms
import Vapor

extension Request {
    /// Stream `ByteBuffer`s from a `Request.Body`
    public var asyncThrowingChannel: AsyncThrowingChannel<ByteBuffer, any Error> {
        let channel = AsyncThrowingChannel<ByteBuffer, any Error>(ByteBuffer.self)
        
        self.body.drain { streamResult in
            Task {
                switch streamResult {
                case .buffer(let byteBuffer):
                    await channel.send(byteBuffer)
                case .error(let error):
                    await channel.fail(error)
                case .end:
                    channel.finish()
                }
            }
            return self.eventLoop.makeSucceededVoidFuture()
        }
        
        return channel
    }
}

