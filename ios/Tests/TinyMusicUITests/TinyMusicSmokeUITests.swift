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
            // 断言用的是中文 label；固定成 zh，测的才是文案而不是宿主系统语言。
            "-uiTestLanguage", "zh",
        ]
    }

    func testLaunchWithStubShowsLibrary() {
        let app = XCUIApplication()
        app.launchArguments = launchArguments
        app.launch()
        XCTAssertTrue(app.staticTexts["歌单"].waitForExistence(timeout: 30))
    }

    func testLyricsSwipeBackReturnsToCover() {
        let app = XCUIApplication()
        app.launchArguments = launchArguments + ["-autoPlay", "-screen", "lyrics"]
        app.launch()
        XCTAssertTrue(app.buttons["返回封面"].waitForExistence(timeout: 30))

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(app.buttons["关闭播放器"].waitForExistence(timeout: 10))
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

    func testLanguageSwitchesImmediatelyWithoutRestart() {
        let app = XCUIApplication()
        app.launchArguments = launchArguments + ["-screen", "settings"]
        app.launch()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 30))

        // 语言行 → 独立选择页，选中后必须留在本页（不能弹回设置）。
        let languageRow = app.buttons["settings.language"]
        XCTAssertTrue(languageRow.waitForExistence(timeout: 10))
        languageRow.tap()

        XCTAssertTrue(app.navigationBars["语言"].waitForExistence(timeout: 10))
        let english = app.descendants(matching: .any)["settings.language.row.en"].firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 10))
        english.tap()

        // 语言页没有关闭：标题与选项当场换成英文。
        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["settings.language.row.zh"].firstMatch.exists)
        // 底部标签栏也跟着换，而不是只换当前页。
        XCTAssertTrue(app.tabBars.buttons["Favorites"].waitForExistence(timeout: 5))

        // 返回设置页：整页（含其它分节）已是英文，无需重启。
        app.navigationBars["Language"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["S3 Storage"].waitForExistence(timeout: 10))

        // 再切回简体中文，同样停留在语言页并立即整页恢复。
        app.buttons["settings.language"].tap()
        XCTAssertTrue(app.navigationBars["Language"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["settings.language.row.zh"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["语言"].waitForExistence(timeout: 10))
        app.navigationBars["语言"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["S3 网盘"].waitForExistence(timeout: 10))
    }

    func testSettingsShowsSupportRows() {
        let app = XCUIApplication()
        app.launchArguments = launchArguments + ["-screen", "settings"]
        app.launch()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 30))

        // 支持入口在版本信息上面；小屏可能要先往上滚一屏。
        let rate = app.descendants(matching: .any)["settings.rateApp"].firstMatch
        var swipes = 0
        while !rate.exists && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.shareApp"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.feedback"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["版本"].exists)
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
