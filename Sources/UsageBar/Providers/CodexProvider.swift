import Foundation

enum CodexProvider {
    private static var authURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
    }

    private struct Auth: Decodable {
        struct Tokens: Decodable {
            var access_token: String
            var refresh_token: String?
            var account_id: String?
            var id_token: String?
        }
        var tokens: Tokens
    }

    private struct RefreshedTokens {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
    }

    private struct UsageResponse: Decodable {
        struct Window: Decodable {
            let used_percent: Double
            let reset_at: Double?
        }
        struct RateLimit: Decodable {
            let primary_window: Window?
            let secondary_window: Window?
        }
        let plan_type: String?
        let rate_limit: RateLimit?
    }

    static func fetch() async -> ProviderUsage {
        let provider = AIProvider.codex
        guard let data = try? Data(contentsOf: authURL),
              var auth = try? JSONDecoder().decode(Auth.self, from: data)
        else {
            return ProviderUsage(provider: provider, state: .needsToken, windows: [], plan: nil, hint: nil)
        }

        var result = await request(token: auth.tokens.access_token, accountId: auth.tokens.account_id)

        if result.state == .authExpired,
           let refresh = auth.tokens.refresh_token,
           let refreshed = await refreshAccessToken(refresh) {
            auth.tokens.access_token = refreshed.accessToken
            // The refresh endpoint rotates the refresh token; persist the new one or the next
            // refresh (ours or the codex CLI's) fails.
            if let newRefresh = refreshed.refreshToken { auth.tokens.refresh_token = newRefresh }
            if let newID = refreshed.idToken { auth.tokens.id_token = newID }
            persistRefreshedTokens(auth.tokens)
            result = await request(token: auth.tokens.access_token, accountId: auth.tokens.account_id)
        }
        return result
    }

    private static func request(token: String, accountId: String?) async -> ProviderUsage {
        let provider = AIProvider.codex
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let accountId { req.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id") }
        req.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        return ProviderUsage.fromHTTP(await performUsageRequest(req), provider: provider) { body in
            let parsed = try JSONDecoder().decode(UsageResponse.self, from: body)
            var windows: [UsageWindow] = []
            if let window = parsed.rate_limit?.primary_window {
                windows.append(UsageWindow(label: "5h", usedPercent: window.used_percent, resetsAt: epochDate(window.reset_at)))
            }
            if let window = parsed.rate_limit?.secondary_window {
                windows.append(UsageWindow(label: "7d", usedPercent: window.used_percent, resetsAt: epochDate(window.reset_at)))
            }
            return ProviderUsage(provider: provider, state: .ok, windows: windows, plan: parsed.plan_type, hint: nil)
        }
    }

    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    private static func refreshAccessToken(_ refreshToken: String) async -> RefreshedTokens? {
        var req = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "openid profile email"
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let (body, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let token = json["access_token"] as? String
        else { return nil }
        return RefreshedTokens(
            accessToken: token,
            refreshToken: json["refresh_token"] as? String,
            idToken: json["id_token"] as? String
        )
    }

    /// Merge refreshed tokens into the existing auth.json instead of re-encoding our own model, so we
    /// never drop keys the codex CLI relies on (including ones we don't model). Also bump last_refresh.
    private static func persistRefreshedTokens(_ tokens: Auth.Tokens) {
        guard let data = try? Data(contentsOf: authURL),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }

        var tokenDict = (json["tokens"] as? [String: Any]) ?? [:]
        tokenDict["access_token"] = tokens.access_token
        if let refresh = tokens.refresh_token { tokenDict["refresh_token"] = refresh }
        if let idToken = tokens.id_token { tokenDict["id_token"] = idToken }
        if let accountId = tokens.account_id { tokenDict["account_id"] = accountId }
        json["tokens"] = tokenDict
        json["last_refresh"] = ISO8601DateFormatter().string(from: Date())

        guard let output = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? output.write(to: authURL, options: .atomic)
    }
}
