# VaporUploads

## Demonstrating File Uploads in Vapor 4

## Basics

Files get sent over the internet in different ways. Vapor supports three that I’m aware of. Collecting data in the request, streaming data in a request, and streaming data in WebSockets.

Vapor provides a handy `File` type that can be used.

## Collect

You can upload files on a `POST` and collect all the incoming bytes with `body: .collect(maxSize)` as seen in [routes.swift:11](https://github.com/mcritz/VaporUploads/blob/68d53018f56f0355995a9de20a610a38a57fdec2/Sources/App/routes.swift#L11).

This is straightforward. Increase the maxSize value and you’ll use that much more system RAM. The body will collect common inbound encodings including JSON and form/multipart.

## HTTP Streaming

You can also upload files on a `POST` and *stream* the incoming bytes for handling as seen in [routes.swift:18](https://github.com/mcritz/VaporUploads/blob/68d53018f56f0355995a9de20a610a38a57fdec2/Sources/App/routes.swift#L18) and [StreamController.swift:24](https://github.com/mcritz/VaporUploads/blob/68d53018f56f0355995a9de20a610a38a57fdec2/Sources/App/Controllers/StreamController.swift#L24)

## WebSocket Streaming

Not yet in this repository, but worth noting for its novelty and performance potential is that you can stream binary data over WebSockets. The strategy is fairly similar to HTTP Streaming because you’ll read inbound bytes and handle them with `Promise` and `Future` types, but the implementation relies on the WebSocket API. 

So, you need to set up the websocket connection, handle inbound bytes, communicate outcomes to the client, and finally close the connection when appropriate. If you want, I can provide a proof of concept example. Let me know on twitter: [@mike_critz](https://twitter.com/mike_critz)

