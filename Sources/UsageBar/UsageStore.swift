import Foundation

@MainActor
final class UsageStore {
    private(set) var providers: [ProviderUsage] = AIProvider.allCases.map { .placeholder($0) }
    private(set) var lastUpdated: Date?
    var onUpdate: (() -> Void)?

    private var lastFetched: [AIProvider: Date] = [:]
    private var lastStatusFetched: [AIProvider: Date] = [:]
    private var statusBackoffUntil: [AIProvider: Date] = [:]
    private var blockedUntil: [AIProvider: Date] = [:]
    private var inFlight: Set<AIProvider> = []

    /// Refresh providers that are due and not backed off. `force` (a user-initiated "Refresh
    /// Now") ignores the min-interval but still respects an active Retry-After block, so we
    /// never deepen a 429 penalty.
    func tick(force: Bool) async {
        let now = Date()
        var fetchedUsage = false
        var didWork = false
        let requests = providers.enumerated().compactMap { index, providerUsage -> FetchRequest? in
            let provider = providerUsage.provider
            let fetchUsage = shouldFetchUsage(provider, now: now, force: force)
            let fetchStatus = shouldFetchStatus(provider, now: now, force: force)
            guard fetchUsage || fetchStatus else { return nil }
            return FetchRequest(
                index: index,
                provider: provider,
                fetchUsage: fetchUsage,
                fetchStatus: fetchStatus
            )
        }
        let secrets = ProviderSecrets.load(for: requests.filter(\.fetchUsage).map(\.provider))

        await withTaskGroup(of: FetchResult.self) { group in
            for request in requests {
                didWork = true
                inFlight.insert(request.provider)
                if request.fetchUsage { fetchedUsage = true }
                group.addTask {
                    let pair = await ProviderFetchCoordinator.fetchPair(
                        provider: request.provider,
                        secrets: secrets,
                        fetchUsage: request.fetchUsage,
                        fetchStatus: request.fetchStatus
                    )
                    return FetchResult(
                        index: request.index,
                        provider: request.provider,
                        usage: pair.usage,
                        status: pair.status,
                        fetchedUsage: request.fetchUsage,
                        fetchedStatus: request.fetchStatus
                    )
                }
            }
            for await item in group {
                inFlight.remove(item.provider)
                if let result = item.usage {
                    if let retry = result.retryAfter {
                        blockedUntil[item.provider] = Date().addingTimeInterval(retry)
                    }
                    providers[item.index] = providers[item.index].merging(fetched: result)
                    if item.fetchedUsage, result.state.stampsFetchInterval {
                        lastFetched[item.provider] = Date()
                    }
                }
                if item.fetchedStatus {
                    if let status = item.status {
                        providers[item.index].serviceStatus = status
                        lastStatusFetched[item.provider] = Date()
                        statusBackoffUntil[item.provider] = nil
                    } else {
                        // Transient failure: keep the last known status and retry sooner.
                        statusBackoffUntil[item.provider] = Date().addingTimeInterval(ProviderStatusFetcher.failureRetryInterval)
                    }
                }
            }
        }

        if didWork {
            if fetchedUsage {
                lastUpdated = Date()
            }
            onUpdate?()
        }
    }

    /// One-shot fetch for CLI diagnostics; ignores min-interval gating.
    static func fetchSnapshot(providers: [AIProvider] = AIProvider.allCases) async -> [ProviderFetchCoordinator.Result] {
        await ProviderFetchCoordinator.fetch(
            providers: providers,
            secrets: ProviderSecrets.load(for: providers),
            includeStatus: true
        )
    }

    private func shouldFetchUsage(_ provider: AIProvider, now: Date, force: Bool) -> Bool {
        if inFlight.contains(provider) { return false }
        if let blocked = blockedUntil[provider], now < blocked { return false }
        if force { return true }
        guard let last = lastFetched[provider] else { return true }
        return now.timeIntervalSince(last) >= provider.minInterval
    }

    private func shouldFetchStatus(_ provider: AIProvider, now: Date, force: Bool) -> Bool {
        if inFlight.contains(provider) { return false }
        if force { return true }
        if let backoff = statusBackoffUntil[provider], now < backoff { return false }
        guard let last = lastStatusFetched[provider] else { return true }
        return now.timeIntervalSince(last) >= ProviderStatusFetcher.minInterval
    }

    var secondsUntilNextRefresh: TimeInterval {
        let now = Date()
        let nextDates = providers.flatMap { providerUsage -> [Date] in
            let provider = providerUsage.provider
            guard !inFlight.contains(provider) else { return [] }

            let intervalDate = lastFetched[provider]?.addingTimeInterval(provider.minInterval) ?? now
            let usageDate = blockedUntil[provider].map { max($0, intervalDate) } ?? intervalDate
            let statusDate: Date
            if let backoff = statusBackoffUntil[provider] {
                statusDate = backoff
            } else if let last = lastStatusFetched[provider] {
                statusDate = last.addingTimeInterval(ProviderStatusFetcher.minInterval)
            } else {
                statusDate = now
            }
            return [usageDate, statusDate]
        }

        guard let next = nextDates.min() else { return 1 }
        return max(1, next.timeIntervalSince(now))
    }
}

private struct FetchRequest: Sendable {
    let index: Int
    let provider: AIProvider
    let fetchUsage: Bool
    let fetchStatus: Bool
}

private struct FetchResult: Sendable {
    let index: Int
    let provider: AIProvider
    let usage: ProviderUsage?
    let status: ServiceStatus?
    let fetchedUsage: Bool
    let fetchedStatus: Bool
}
