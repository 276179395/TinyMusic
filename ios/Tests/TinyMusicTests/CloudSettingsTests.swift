import Foundation
import Testing
@testable import TinyMusic

struct CloudSettingsTests {
    @Test func eqRoundTripsThroughKVS() throws {
        var settings = IosSettings()
        settings.s3Endpoint = "https://s3.example.com"
        settings.s3Bucket = "music"
        var eq = EQState()
        eq.enabled = true
        eq.gains = EQLibrary.preset(id: "rock")!.gains
        eq.preamp = EQLibrary.preset(id: "rock")!.preamp
        eq.presetID = "rock"

        let payload = CloudSettings(settings: settings, eq: eq)
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(CloudSettings.self, from: data)
        #expect(decoded.eq?.enabled == true)
        #expect(decoded.eq?.gains == eq.gains)
        #expect(decoded.eq?.presetID == "rock")
    }

    @Test func oldPayloadWithoutEQStillDecodes() throws {
        let json = #"{"s3Enabled":true,"s3Endpoint":"https://s3.example.com","s3Region":"us-east-1","s3Bucket":"music","s3Prefix":"TinyMusic","s3PathStyle":true,"updatedAt":1,"deviceId":"d"}"#
        let decoded = try JSONDecoder().decode(CloudSettings.self, from: Data(json.utf8))
        #expect(decoded.eq == nil)
        #expect(decoded.s3Bucket == "music")
    }
}
