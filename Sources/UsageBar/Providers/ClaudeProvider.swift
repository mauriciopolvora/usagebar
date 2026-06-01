import Foundation

enum ClaudeProvider {
    private struct Creds: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let subscriptionType: String?
            let expiresAt: Double?   // epoch milliseconds
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

    static func fetch() async -> ProviderUsage {
        let provider = AIProvider.claude
        guard var creds = loadCreds() else {
            return ProviderUsage(provider: provider, state: .needsToken, windows: [], plan: nil, hint: nil)
        }

        // The OAuth access token is short-lived and rotated by Claude Code. If it's already expired,
        // nudge the CLI to refresh its keychain entry before spending a (rate-limited) request.
        if isExpired(creds), let refreshed = await refreshViaCLI() {
            creds = refreshed
        }

        var result = await request(creds: creds)

        // A 401 means the token we read is dead. Let Claude Code refresh the keychain, then retry once.
        if result.state == .authExpired, let refreshed = await refreshViaCLI() {
            result = await request(creds: refreshed)
        }
        return result
    }

    private static func request(creds: Creds) async -> ProviderUsage {
        let provider = AIProvider.claude
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

    /// Read credentials fresh from the keychain on every fetch (no process-lifetime cache) so we
    /// always see whatever Claude Code last refreshed.
    private static func loadCreds() -> Creds? {
        guard let raw = Keychain.genericPassword(service: Keychain.claudeService),
              let data = raw.data(using: .utf8),
              let creds = try? JSONDecoder().decode(Creds.self, from: data)
        else { return nil }
        return creds
    }

    /// Missing `expiresAt` (e.g. long-lived setup tokens) is treated as not-expired; the API decides.
    private static func isExpired(_ creds: Creds) -> Bool {
        guard let ms = creds.claudeAiOauth.expiresAt else { return false }
        return Date().timeIntervalSince1970 >= ms / 1000
    }

    /// We never mint tokens ourselves — that would risk invalidating Claude Code's refresh token.
    /// Instead we run `claude auth status`, which makes Claude Code refresh its own keychain entry,
    /// then re-read it. Returns refreshed credentials only if they are now valid. Throttled.
    private static func refreshViaCLI() async -> Creds? {
        guard await refreshThrottle.shouldAttempt() else { return nil }
        await runClaudeAuthStatus()
        guard let creds = loadCreds(), !isExpired(creds) else { return nil }
        return creds
    }

    private static let refreshThrottle = RefreshThrottle()

    private actor RefreshThrottle {
        private var lastAttempt: Date?
        private let cooldown: TimeInterval = 60

        func shouldAttempt() -> Bool {
            let now = Date()
            if let last = lastAttempt, now.timeIntervalSince(last) < cooldown { return false }
            lastAttempt = now
            return true
        }
    }

    /// Runs `claude auth status` via a login shell so it resolves on the user's PATH even when the
    /// app was launched at login with a minimal environment. Output is discarded; a timeout guards
    /// against a hung CLI.
    private static func runClaudeAuthStatus() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "claude auth status"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                cont.resume()
                return
            }

            DispatchQueue.global().async {
                let deadline = Date().addingTimeInterval(10)
                while process.isRunning, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
                cont.resume()
            }
        }
    }
}
