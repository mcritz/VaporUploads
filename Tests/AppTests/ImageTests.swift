//
//  File.swift
//  
//
//  Created by Michael Critz on 4/13/20.
//

@testable import App
import XCTVapor

final class ImageTests: XCTestCase {
    var app: Application!
    
    override func setUp() {
        app = Application(.testing)
        try! configure(app)
    }
    override func tearDown() {
        app.shutdown()
    }
    
    func testImages() throws {
        try app.test(.GET, "images") { res in
            XCTAssertEqual(res.status, .ok)
        }
    }
}
