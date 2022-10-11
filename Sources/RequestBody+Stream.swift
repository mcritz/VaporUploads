//
//  RequestBody+Stream.swift
//  
//
//  Created by Michael Critz on 10/4/22.
//

import AsyncAlgorithms
import Vapor

extension Body {
    public var bytes: AsyncThrowingStream<ByteBuffer, Error> {
        return AsyncThrowingStream { continuation in
            body.drain { streamResult in
                switch streamResult {
                case .buffer(let byteBuffer):
                    continuation.yield(byteBuffer)
                case .error(let error):
                    continuation.finish(throwing: error)
                case .end:
                    continuation.finish()
                }
            }
        }
    }
}
