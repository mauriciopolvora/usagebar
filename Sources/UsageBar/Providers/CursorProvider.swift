import Foundation

enum CursorProvider {
    private static let needsTokenHint = "Needs token - use Set Cursor Token below"

    private struct Summary: Decodable {
        struct Individual: Decodable {
            struct Plan: Decodable {
                let autoPercentUsed: Double?
                let apiPercentUsed: Double?
            }
            let plan: Plan?
        }
        let membershipType: String?
        let billingCycleEnd: String?
        let individualUsage: Individual?
    }

    static func fetch(token: String?) async -> ProviderUsage {
        let provider = AIProvider.cursor
        guard let token, !token.isEmpty else {
            return ProviderUsage(
                provider: provider,
                state: .needsToken,
                windows: [],
                plan: nil,
                hint: needsTokenHint
            )
        }

        var req = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        req.setValue("WorkosCursorSessionToken=\(token)", forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        return ProviderUsage.fromHTTP(await performUsageRequest(req), provider: provider) { body in
            let parsed = try JSONDecoder().decode(Summary.self, from: body)
            guard let plan = parsed.individualUsage?.plan else {
                return ProviderUsage(
                    provider: provider,
                    state: .error("no plan usage"),
                    windows: [],
                    plan: parsed.membershipType,
                    hint: nil
                )
            }

            let resetsAt = isoDate(parsed.billingCycleEnd)
            var windows: [UsageWindow] = []
            if let auto = plan.autoPercentUsed {
                windows.append(UsageWindow(label: "auto", usedPercent: auto, resetsAt: resetsAt))
            }
            if let api = plan.apiPercentUsed {
                windows.append(UsageWindow(label: "api", usedPercent: api, resetsAt: resetsAt))
            }
            if windows.isEmpty {
                return ProviderUsage(
                    provider: provider,
                    state: .error("unrecognized response"),
                    windows: [],
                    plan: parsed.membershipType,
                    hint: nil
                )
            }
            return ProviderUsage(
                provider: provider,
                state: .ok,
                windows: windows,
                plan: parsed.membershipType,
                hint: nil
            )
        }
    }
}
