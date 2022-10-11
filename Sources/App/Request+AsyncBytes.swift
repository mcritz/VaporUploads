//
//  Request+AsyncBytes.swift
//  
//
//  Created by Michael Critz on 10/9/22.
//

import Vapor

extension Request {
    /// Stream `ByteBuffer`s from a `Request.Body`
    public var asyncByteBufferStream: AsyncThrowingStream<ByteBuffer, Error> {
        AsyncThrowingStream { continuation in
            self.body.drain { streamResult in
                switch streamResult {
                case .buffer(let byteBuffer):
                    continuation.yield(byteBuffer)
                case .error(let error):
                    continuation.finish(throwing: error)
                case .end:
                    continuation.finish()
                }
                return self.eventLoop.makeSucceededVoidFuture()
            }
        }
    }
}

