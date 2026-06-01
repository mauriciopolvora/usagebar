import Foundation

/// Keychain-backed credentials passed into provider fetches. Codex reads `~/.codex/auth.json` and
/// Claude reads its keychain item (`Claude Code-credentials`) directly, so neither uses this bundle.
struct ProviderSecrets: Sendable {
    let cursorToken: String?

    static let empty = ProviderSecrets(cursorToken: nil)

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
        return ProviderSecrets(cursorToken: cursorToken)
    }
}
