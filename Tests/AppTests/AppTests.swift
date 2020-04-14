@testable import App
import XCTVapor

final class AppTests: XCTestCase {
    func testHelloWorld() throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)

        try app.test(.GET, "hello") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Hello, world!")
        }

    }
    
    func testTodo() throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)
        
        try app.test(.GET, "todos") { res in
            XCTAssertEqual(res.status, .ok)
        }
        
        try app.test(.POST, "todos", body: nil) { res in
            XCTAssertEqual(res.status, HTTPStatus.unsupportedMediaType)
        }
        
        let newTodo = Todo(id: nil, title: "New Todo")
        let allocator = ByteBufferAllocator()
        let newTodoBytes = try! JSONEncoder().encodeAsByteBuffer(newTodo, allocator: allocator)
        
        let reqHeaders = HTTPHeaders(dictionaryLiteral: ("content-type", "application/json"))
        
        var postedTodoID = String()
        
        try app.test(.POST, "todos", headers: reqHeaders, body: newTodoBytes) { res in
            XCTAssertEqual(res.status, .ok)
            var mutableRes = res
            let todo = try? mutableRes.body.readJSONDecodable(Todo.self, length: res.body.capacity)
            XCTAssertEqual(todo?.title, newTodo.title)
            postedTodoID = todo!.id!.uuidString
        }
        
        try app.test(.GET, "todos/\(postedTodoID)") { res in
            XCTAssertEqual(res.status, .ok)
            var mutableRes = res
            let todo = try? mutableRes.body.readJSONDecodable(Todo.self, length: res.body.capacity)
            XCTAssertEqual(todo?.title, newTodo.title)
        }
    }

}
