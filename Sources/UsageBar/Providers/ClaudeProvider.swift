import Foundation

enum ClaudeProvider {
    private struct Creds: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let subscriptionType: String?
        }
        let claudeAiOauth: OAuth
    }

    private struct UsageResponse: Decodable {
        struct Window: Decodable {
            let utilization: Double
            let resets_at: String?
        }
        let five_hour: Window?
        let seven_day: Window?
    }

    static func fetch(rawCredentials raw: String?) async -> ProviderUsage {
        let provider = AIProvider.claude
        guard let raw,
              let data = raw.data(using: .utf8),
              let creds = try? JSONDecoder().decode(Creds.self, from: data)
        else {
            return ProviderUsage(provider: provider, state: .needsToken, windows: [], plan: nil, hint: nil)
        }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(creds.claudeAiOauth.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("claude-code/2.1.149", forHTTPHeaderField: "User-Agent")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let plan = creds.claudeAiOauth.subscriptionType
        return ProviderUsage.fromHTTP(await performUsageRequest(req), provider: provider, plan: plan) { body in
            let parsed = try JSONDecoder().decode(UsageResponse.self, from: body)
            var windows: [UsageWindow] = []
            if let window = parsed.five_hour {
                windows.append(UsageWindow(label: "5h", usedPercent: window.utilization, resetsAt: isoDate(window.resets_at)))
            }
            if let window = parsed.seven_day {
                windows.append(UsageWindow(label: "7d", usedPercent: window.utilization, resetsAt: isoDate(window.resets_at)))
            }
            return ProviderUsage(provider: provider, state: .ok, windows: windows, plan: plan, hint: nil)
        }
    }
}
