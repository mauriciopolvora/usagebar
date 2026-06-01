import Foundation

enum AIProvider: String, CaseIterable, Hashable, Sendable {
    case codex = "Codex"
    case claude = "Claude"
    case cursor = "Cursor"

    var displayName: String { rawValue }

    var cliName: String {
        switch self {
        case .codex: return "codex"
        case .claude: return "claude"
        case .cursor: return "cursor"
        }
    }

    var minInterval: TimeInterval {
        switch self {
        case .codex: return 180    // 3 min
        case .claude: return 900   // 15 min — Anthropic throttles hard
        case .cursor: return 180   // 3 min
        }
    }

    var statusSource: StatusSource? {
        switch self {
        case .codex:
            return StatusSource(label: "OpenAI", baseURL: URL(string: "https://status.openai.com")!)
        case .claude:
            return StatusSource(label: "Claude", baseURL: URL(string: "https://status.claude.com")!)
        case .cursor:
            return StatusSource(label: "Cursor", baseURL: URL(string: "https://status.cursor.com")!)
        }
    }

    static func matching(cliName: String) -> AIProvider? {
        allCases.first { $0.cliName == cliName.lowercased() }
    }

    static func matchingDumpFilter(_ filter: String) -> [AIProvider] {
        if filter == "all" { return allCases }
        guard let provider = matching(cliName: filter) else { return [] }
        return [provider]
    }

    /// `secrets` supplies the Cursor token. Codex and Claude read their own credentials directly.
    func fetchUsage(secrets: ProviderSecrets) async -> ProviderUsage {
        switch self {
        case .codex: return await CodexProvider.fetch()
        case .claude: return await ClaudeProvider.fetch()
        case .cursor: return await CursorProvider.fetch(token: secrets.cursorToken)
        }
    }
}

struct StatusSource: Sendable {
    let label: String
    let baseURL: URL

    var apiURL: URL {
        baseURL.appendingPathComponent("api/v2/status.json")
    }
}
