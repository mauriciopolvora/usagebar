import Foundation

enum ProviderState: Equatable, Sendable {
    case ok
    case needsToken
    case authExpired
    case error(String)
}

enum ServiceStatusLevel: String, Sendable {
    case operational
    case degraded
    case outage
    case maintenance
    case unknown
}

struct ServiceStatus: Sendable {
    let providerName: String
    let level: ServiceStatusLevel
    let detail: String?
    let updatedAt: Date?
}

struct UsageWindow: Sendable {
    let label: String       // e.g. "5h", "7d", "auto", "api"
    let usedPercent: Double  // 0...100
    let resetsAt: Date?

    var displayLabel: String {
        switch label {
        case "5h": return "Session"
        case "7d": return "Week"
        case "auto": return "Auto"
        case "api": return "API"
        default: return label
        }
    }
}

struct ProviderUsage: Sendable {
    let provider: AIProvider
    var state: ProviderState
    var windows: [UsageWindow]
    var plan: String?
    var hint: String?
    var serviceStatus: ServiceStatus? = nil
    var stale: Bool = false
    var retryAfter: TimeInterval? = nil

    var name: String { provider.displayName }

    static func placeholder(_ provider: AIProvider) -> ProviderUsage {
        ProviderUsage(provider: provider, state: .ok, windows: [], plan: nil, hint: nil)
    }

    /// On a transient failure (e.g. a 429), keep showing the last-good value marked stale
    /// rather than flashing an error. Permanent states (needsToken/authExpired) still surface.
    func merging(fetched new: ProviderUsage) -> ProviderUsage {
        var next = new
        next.serviceStatus = serviceStatus
        guard next.state != .ok else { return next }
        if case .error = next.state, state == .ok, !windows.isEmpty {
            var kept = self
            kept.stale = true
            return kept
        }
        return next
    }

    func cliLine(status: ServiceStatus? = nil) -> String {
        let detail: String
        if state == .ok, !windows.isEmpty {
            detail = windows.map {
                "\($0.label)=\(Int($0.usedPercent.rounded()))% (resets \(formatReset($0.resetsAt)))"
            }.joined(separator: ", ")
        } else {
            detail = state.cliDetail
        }
        let planText = plan.map { " [\($0)]" } ?? ""
        let statusText = status.map { " | \($0.providerName) status: \($0.level.rawValue)" } ?? ""
        return "\(name)\(planText): \(detail)\(statusText)"
    }

    /// Maps a shared usage HTTP outcome to a provider result. `parseOK` handles success-body parsing;
    /// decode failures become a transient `"network"` error.
    static func fromHTTP(
        _ outcome: UsageHTTPOutcome,
        provider: AIProvider,
        plan: String? = nil,
        hint: String? = nil,
        parseOK: (Data) throws -> ProviderUsage
    ) -> ProviderUsage {
        switch outcome {
        case .authExpired:
            return ProviderUsage(provider: provider, state: .authExpired, windows: [], plan: plan, hint: hint)
        case .rateLimited(let retry):
            return ProviderUsage(
                provider: provider,
                state: .error("rate limited"),
                windows: [],
                plan: plan,
                hint: hint,
                retryAfter: retry
            )
        case .http(let code):
            return ProviderUsage(provider: provider, state: .error("HTTP \(code)"), windows: [], plan: nil, hint: hint)
        case .network:
            return ProviderUsage(provider: provider, state: .error("network"), windows: [], plan: nil, hint: hint)
        case .ok(let body):
            do {
                return try parseOK(body)
            } catch {
                return ProviderUsage(provider: provider, state: .error("network"), windows: [], plan: nil, hint: hint)
            }
        }
    }
}

extension ProviderState {
    var dumpName: String {
        switch self {
        case .ok: return "ok"
        case .needsToken: return "needsToken"
        case .authExpired: return "authExpired"
        case .error(let message): return "error: \(message)"
        }
    }

    var cliDetail: String {
        switch self {
        case .ok: return "ok"
        case .needsToken: return "needs token"
        case .authExpired: return "auth expired"
        case .error(let message): return "error: \(message)"
        }
    }

    /// Whether a completed fetch should start the min-interval clock.
    var stampsFetchInterval: Bool {
        switch self {
        case .ok, .needsToken, .authExpired: return true
        case .error: return false
        }
    }
}

enum ResetDisplayStyle {
    case compact
    case menuRow
}

enum UsageHTTPOutcome: Sendable {
    case ok(Data)
    case authExpired
    case rateLimited(TimeInterval)
    case http(Int)
    case network
}

func performUsageRequest(_ req: URLRequest) async -> UsageHTTPOutcome {
    do {
        let (body, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { return .authExpired }
        if code == 429 { return .rateLimited(retryAfterSeconds(resp)) }
        guard code == 200 else { return .http(code) }
        return .ok(body)
    } catch {
        return .network
    }
}

/// Seconds to wait after a 429, from the `Retry-After` header (numeric seconds), defaulting
/// to 5 minutes when absent.
func retryAfterSeconds(_ resp: URLResponse?) -> TimeInterval {
    if let http = resp as? HTTPURLResponse,
       let value = http.value(forHTTPHeaderField: "Retry-After"),
       let secs = TimeInterval(value.trimmingCharacters(in: .whitespaces)) {
        return secs
    }
    return 300
}

func isoDate(_ string: String?) -> Date? {
    guard let string else { return nil }
    if let date = isoDateFormatter.date(from: string) { return date }
    return ISO8601DateFormatter().date(from: string)
}

func epochDate(_ secs: Double?) -> Date? {
    guard let secs, secs > 0 else { return nil }
    return Date(timeIntervalSince1970: secs)
}

func formatReset(_ date: Date?, style: ResetDisplayStyle = .compact) -> String {
    guard let date else { return "" }
    let secs = date.timeIntervalSinceNow
    if secs <= 0 { return "now" }

    switch style {
    case .compact:
        let mins = Int(secs / 60)
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    case .menuRow:
        if secs < 48 * 3600 {
            let mins = Int(secs / 60)
            return mins < 60 ? "in \(mins)m" : "in \(mins / 60)h"
        }
        return menuRowResetDateFormatter.string(from: date)
    }
}

private let isoDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let menuRowResetDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter
}()
