import Foundation

enum ProviderStatusFetcher {
    static let minInterval: TimeInterval = 900

    static func fetch(for provider: AIProvider) async -> ServiceStatus? {
        guard let source = provider.statusSource else { return nil }
        var req = URLRequest(url: source.apiURL)
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                return ServiceStatus(providerName: source.label, level: .unknown, detail: nil, updatedAt: nil)
            }

            let decoded = try decoder.decode(StatusPageResponse.self, from: data)
            return ServiceStatus(
                providerName: source.label,
                level: level(for: decoded.status.indicator),
                detail: decoded.status.description,
                updatedAt: decoded.page?.updatedAt
            )
        } catch {
            return ServiceStatus(providerName: source.label, level: .unknown, detail: nil, updatedAt: nil)
        }
    }

    private static func level(for indicator: String) -> ServiceStatusLevel {
        switch indicator {
        case "none": return .operational
        case "minor": return .degraded
        case "major", "critical": return .outage
        case "maintenance": return .maintenance
        default: return .unknown
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = isoDate(raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date")
            }
            return date
        }
        return decoder
    }()
}

private struct StatusPageResponse: Decodable {
    struct Page: Decodable {
        let updatedAt: Date?

        private enum CodingKeys: String, CodingKey {
            case updatedAt = "updated_at"
        }
    }

    struct Status: Decodable {
        let indicator: String
        let description: String?
    }

    let page: Page?
    let status: Status
}
