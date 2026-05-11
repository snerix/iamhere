import Foundation

/// IPPure-backed current-egress lookup.
///
/// Public API docs: `GET https://my.ippure.com/v1/info`. The endpoint is
/// documented as beta, so fields beyond the stable location / ASN core are
/// intentionally decoded as optional and mapped into `IPDataModel.purity`.
struct IPPureProvider: IPProvider {
    let name = "IPPure"
    private let endpoint: URL
    private let sessionFactory: @Sendable () -> URLSession

    init(
        endpoint: URL = URL(string: "https://my.ippure.com/v1/info")!,
        sessionFactory: @escaping @Sendable () -> URLSession = IPPureProvider.makeSession
    ) {
        self.endpoint = endpoint
        self.sessionFactory = sessionFactory
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": AppUserAgent.value
        ]
        return URLSession(configuration: config)
    }

    func fetch() async throws -> IPDataModel {
        let session = sessionFactory()
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw IPServiceError.from(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw IPServiceError.transport(message: "Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw IPServiceError.http(statusCode: http.statusCode)
        }

        do {
            let raw = try JSONDecoder().decode(IPPureRawResponse.self, from: data)
            return Self.map(raw)
        } catch {
            throw IPServiceError.decoding(message: error.localizedDescription)
        }
    }

    static func map(_ raw: IPPureRawResponse) -> IPDataModel {
        let isResidential = raw.isResidential
        let isBroadcast = raw.isBroadcast
        let type = raw.ipType ?? isResidential.map { $0
            ? "Residential"
            : "Data center"
        }
        let source = raw.ipSource ?? isBroadcast.map { $0
            ? "Broadcast"
            : "Native"
        }

        return IPDataModel(
            ip: raw.ip,
            countryAlpha2: raw.countryCode.uppercased(),
            network: .init(
                cidr: raw.cidr,
                autonomousSystem: .init(
                    asn: raw.asn,
                    name: raw.asOrganization,
                    organization: raw.asOrganization,
                    country: nil,
                    rir: nil
                )
            ),
            location: .init(
                city: raw.city.flatMap { $0.isEmpty ? nil : $0 },
                country: raw.country,
                timezone: raw.timezone,
                latitude: raw.latitude,
                longitude: raw.longitude
            ),
            purity: .init(
                fraudScore: raw.fraudScore,
                cloudflareScore: raw.cloudflareBotScore.map(Self.cloudflareRiskCoefficient),
                humanBotRatio: raw.humanBotRatio,
                ipSource: source,
                ipType: type,
                isResidential: isResidential,
                isBroadcast: isBroadcast
            )
        )
    }

    private static func cloudflareRiskCoefficient(from botScore: Int) -> Int {
        min(max(100 - botScore, 0), 100)
    }
}

struct IPPureRawResponse: Decodable, Equatable, Sendable {
    let ip: String
    let asn: Int
    let asOrganization: String
    let country: String
    let countryCode: String
    let region: String?
    let regionCode: String?
    let city: String?
    let timezone: String
    let longitude: Double
    let latitude: Double
    let postalCode: String?
    let cidr: String?
    let fraudScore: Int?
    let isResidential: Bool?
    let isBroadcast: Bool?
    let humanBotRatio: Double?
    let ipSource: String?
    let ipType: String?
    let cloudflareBotScore: Int?
    let userAgent: String?

    fileprivate enum CodingKeys: String, CodingKey {
        case ip
        case asn
        case asOrganization
        case country
        case countryCode
        case region
        case regionCode
        case city
        case timezone
        case longitude
        case latitude
        case postalCode
        case cidr
        case fraudScore
        case isResidential
        case isBroadcast
        case humanBotRatio
        case humanBotRatioSnake = "human_bot_ratio"
        case asnHumanBotRatio
        case asnHumanBotRatioSnake = "asn_human_bot_ratio"
        case ipSource
        case ipSourceSnake = "ip_source"
        case ipType
        case ipTypeSnake = "ip_type"
        case cloudflareScore
        case cloudflareScoreSnake = "cloudflare_score"
        case cfScore
        case cfScoreSnake = "cf_score"
        case userAgent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ip = try c.decode(String.self, forKey: .ip)
        asn = try c.decodeFlexibleInt(forKey: .asn)
        asOrganization = try c.decode(String.self, forKey: .asOrganization)
        country = try c.decode(String.self, forKey: .country)
        countryCode = try c.decode(String.self, forKey: .countryCode)
        region = try c.decodeIfPresent(String.self, forKey: .region)
        regionCode = try c.decodeIfPresent(String.self, forKey: .regionCode)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        timezone = try c.decode(String.self, forKey: .timezone)
        longitude = try c.decodeFlexibleDouble(forKey: .longitude)
        latitude = try c.decodeFlexibleDouble(forKey: .latitude)
        postalCode = try c.decodeIfPresent(String.self, forKey: .postalCode)
        cidr = try c.decodeIfPresent(String.self, forKey: .cidr)
        fraudScore = try c.decodeFlexibleIntIfPresent(forKey: .fraudScore)
        isResidential = try c.decodeIfPresent(Bool.self, forKey: .isResidential)
        isBroadcast = try c.decodeIfPresent(Bool.self, forKey: .isBroadcast)
        humanBotRatio = try c.decodeFlexibleDoubleIfPresent(
            keys: [.humanBotRatio, .humanBotRatioSnake, .asnHumanBotRatio, .asnHumanBotRatioSnake]
        )
        ipSource = try c.decodeStringIfPresent(keys: [.ipSource, .ipSourceSnake])
        ipType = try c.decodeStringIfPresent(keys: [.ipType, .ipTypeSnake])
        cloudflareBotScore = try c.decodeFlexibleIntIfPresent(
            keys: [.cloudflareScore, .cloudflareScoreSnake, .cfScore, .cfScoreSnake]
        )
        userAgent = try c.decodeIfPresent(String.self, forKey: .userAgent)
    }
}

private extension KeyedDecodingContainer where Key == IPPureRawResponse.CodingKeys {
    func decodeFlexibleInt(forKey key: Key) throws -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let string = try? decode(String.self, forKey: key), let value = Int(string) {
            return value
        }
        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Expected Int or Int string")
        )
    }

    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        try decodeFlexibleIntIfPresent(keys: [key])
    }

    func decodeFlexibleIntIfPresent(keys: [Key]) throws -> Int? {
        for key in keys {
            if let value = try? decode(Int.self, forKey: key) { return value }
            if let string = try? decode(String.self, forKey: key), let value = Int(string) {
                return value
            }
        }
        return nil
    }

    func decodeFlexibleDouble(forKey key: Key) throws -> Double {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let string = try? decode(String.self, forKey: key), let value = Double(string) {
            return value
        }
        throw DecodingError.typeMismatch(
            Double.self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Expected Double or Double string")
        )
    }

    func decodeFlexibleDoubleIfPresent(keys: [Key]) throws -> Double? {
        for key in keys {
            if let value = try? decode(Double.self, forKey: key) { return value }
            if let int = try? decode(Int.self, forKey: key) { return Double(int) }
            if let string = try? decode(String.self, forKey: key), let value = Double(string) {
                return value
            }
        }
        return nil
    }

    func decodeStringIfPresent(keys: [Key]) throws -> String? {
        for key in keys {
            if let value = try? decode(String.self, forKey: key), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
