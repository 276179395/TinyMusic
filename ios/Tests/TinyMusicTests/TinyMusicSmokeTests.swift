import Testing
@testable import TinyMusic

@MainActor
struct TinyMusicSmokeTests {
    @Test func defaultSettingsAreSane() {
        let settings = IosSettings()
        #expect(settings.s3Region == "us-east-1")
        #expect(settings.s3Prefix == "TinyMusic")
        #expect(settings.hasCredentials == false)
    }
}
