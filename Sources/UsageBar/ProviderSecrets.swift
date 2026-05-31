import Foundation

/// Keychain-backed credentials passed into provider fetches. Codex reads `~/.codex/auth.json` directly
/// and does not use this bundle.
struct ProviderSecrets: Sendable {
    let cursorToken: String?
    let claudeCredentials: String?

    static let empty = ProviderSecrets(cursorToken: nil, claudeCredentials: nil)

    static func load(
        for providers: some Sequence<AIProvider>,
        cursorToken override: String? = nil
    ) -> ProviderSecrets {
        let usageProviders = Set(providers)
        let cursorToken: String?
        if let override {
            cursorToken = override
        } else if usageProviders.contains(.cursor) {
            cursorToken = Keychain.cachedGenericPassword(
                service: Keychain.cursorService,
                account: Keychain.cursorAccount
            )
        } else {
            cursorToken = nil
        }
        let claudeCredentials = usageProviders.contains(.claude)
            ? Keychain.cachedGenericPassword(service: Keychain.claudeService)
            : nil
        return ProviderSecrets(cursorToken: cursorToken, claudeCredentials: claudeCredentials)
    }
}
