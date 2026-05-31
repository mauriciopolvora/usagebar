import Foundation

enum ProviderFetchCoordinator {
    struct Result: Sendable {
        let provider: AIProvider
        let usage: ProviderUsage
        let status: ServiceStatus?
    }

    static func fetchPair(
        provider: AIProvider,
        secrets: ProviderSecrets,
        fetchUsage: Bool,
        fetchStatus: Bool
    ) async -> (usage: ProviderUsage?, status: ServiceStatus?) {
        async let usage = fetchUsage ? provider.fetchUsage(secrets: secrets) : nil
        async let status = fetchStatus ? ProviderStatusFetcher.fetch(for: provider) : nil
        return (await usage, await status)
    }

    static func fetch(
        providers: [AIProvider],
        secrets: ProviderSecrets,
        includeStatus: Bool = true
    ) async -> [Result] {
        await withTaskGroup(of: (Int, Result).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    let pair = await fetchPair(
                        provider: provider,
                        secrets: secrets,
                        fetchUsage: true,
                        fetchStatus: includeStatus
                    )
                    return (
                        index,
                        Result(provider: provider, usage: pair.usage!, status: pair.status)
                    )
                }
            }

            var results: [(Int, Result)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
