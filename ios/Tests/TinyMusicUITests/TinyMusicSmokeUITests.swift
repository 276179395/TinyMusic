import XCTest

final class TinyMusicSmokeUITests: XCTestCase {
    private var launchArguments: [String] {
        [
            "-uiTestS3Endpoint", "http://127.0.0.1:9100",
            "-uiTestS3Region", "us-east-1",
            "-uiTestS3Bucket", "music",
            "-uiTestS3Prefix", "TinyMusic",
            "-uiTestS3AK", "test",
            "-uiTestS3SK", "test",
            "-uiTestKeychainService", "cn.carljoy.tinymusic.s3.uitest",
        ]
    }

    func testLaunchWithStubShowsLibrary() {
        let app = XCUIApplication()
        app.launchArguments = launchArguments
        app.launch()
        XCTAssertTrue(app.staticTexts["歌单"].waitForExistence(timeout: 30))
    }

    func testMiniPlayerOpensQueueSheet() {
        let app = XCUIApplication()
        app.launchArguments = launchArguments + ["-autoPlay"]
        app.launch()
        let queueButton = app.buttons["播放列表"]
        XCTAssertTrue(queueButton.waitForExistence(timeout: 30))
        queueButton.tap()
        XCTAssertTrue(app.navigationBars["播放列表"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["关闭"].exists)
    }

    func testCacheTabShowsOfflineCache() {
        let app = XCUIApplication()
        app.launchArguments = launchArguments + ["-screen", "cache"]
        app.launch()
        XCTAssertTrue(app.navigationBars["缓存"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["已占用"].exists)
    }

    func testPlayerShowsTransport() {
        let app = XCUIApplication()
        app.launchArguments = launchArguments + ["-autoPlay", "-screen", "player"]
        app.launch()
        XCTAssertTrue(app.buttons["下一首"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["暂停"].exists || app.buttons["播放"].exists)
    }

    func testEQSheetOpens() {
        let app = XCUIApplication()
        app.launchArguments = launchArguments + ["-autoPlay", "-eqTest", "-screen", "eq"]
        app.launch()
        XCTAssertTrue(app.staticTexts["均衡器"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["启用均衡器"].exists)
        XCTAssertTrue(app.staticTexts["摇滚"].exists)
    }
}
