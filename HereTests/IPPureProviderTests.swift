import Foundation
import Testing

@testable import Here

@Suite("IPPureProvider")
struct IPPureProviderTests {
    @Test func mapsDocumentedResponseEndToEnd() throws {
        let data = Data("""
        {
          "ip": "104.28.123.123",
          "asn": 13335,
          "asOrganization": "Cloudflare, Inc.",
          "country": "United States",
          "countryCode": "US",
          "region": "California",
          "regionCode": "CA",
          "city": "Los Angeles",
          "timezone": "America/Los_Angeles",
          "longitude": "-118.24368",
          "latitude": "34.05223",
          "postalCode": "90012",
          "fraudScore": 75,
          "isResidential": false,
          "isBroadcast": false,
          "humanBotRatio": 82,
          "cloudflareScore": 12,
          "userAgent": "HereTests"
        }
        """.utf8)

        let raw = try JSONDecoder().decode(IPPureRawResponse.self, from: data)
        let model = IPPureProvider.map(raw)

        #expect(model.ip == "104.28.123.123")
        #expect(model.countryAlpha2 == "US")
        #expect(model.location.country == "United States")
        #expect(model.location.city == "Los Angeles")
        #expect(model.location.timezone == "America/Los_Angeles")
        #expect(abs(model.location.latitude - 34.05223) < 0.0001)
        #expect(abs(model.location.longitude - (-118.24368)) < 0.0001)

        #expect(model.network.autonomousSystem.asn == 13335)
        #expect(model.network.autonomousSystem.organization == "Cloudflare, Inc.")
        #expect(model.network.cidr == nil)

        #expect(model.purity?.fraudScore == 75)
        #expect(model.purity?.isResidential == false)
        #expect(model.purity?.isBroadcast == false)
        #expect(model.purity?.ipType == "Data center")
        #expect(model.purity?.ipSource == "Native")
        #expect(model.purity?.humanBotRatio == 82)
        #expect(model.purity?.cloudflareScore == 88)
    }

    @Test func acceptsAlternativeAdvancedFieldNames() throws {
        let data = Data("""
        {
          "ip": "1.1.1.1",
          "asn": "13335",
          "asOrganization": "Cloudflare, Inc.",
          "country": "Australia",
          "countryCode": "AU",
          "timezone": "Australia/Sydney",
          "longitude": 143.211,
          "latitude": -33.494,
          "human_bot_ratio": "0.91",
          "cf_score": "7",
          "ip_source": "Native",
          "ip_type": "Residential"
        }
        """.utf8)

        let raw = try JSONDecoder().decode(IPPureRawResponse.self, from: data)
        let model = IPPureProvider.map(raw)

        #expect(model.network.autonomousSystem.asn == 13335)
        #expect(model.purity?.humanBotRatio == 0.91)
        #expect(model.purity?.cloudflareScore == 93)
        #expect(model.purity?.ipSource == "Native")
        #expect(model.purity?.ipType == "Residential")
    }
}
