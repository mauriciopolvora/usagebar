import AppKit

@main
enum UsageBarApp {
    static func main() async {
        if CommandLine.arguments.contains("--dump") {
            exit(await DumpCLI.run())
        }
        runMenuBarApp()
    }

    @MainActor
    private static func runMenuBarApp() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

enum DumpCLI {
    static func run() async -> Int32 {
        let args = Array(CommandLine.arguments.dropFirst())
        let json = args.contains("--json")
        let selected = AIProvider.matchingDumpFilter(dumpProviderFilter(from: args))
        if selected.isEmpty {
            fputs("usagebar --dump [--provider codex|claude|cursor|all] [--json]\n", stderr)
            return 2
        }

        let results = await UsageStore.fetchSnapshot(providers: selected)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let payload = results.map { DumpProvider(usage: $0.usage, status: $0.status) }
            if let data = try? encoder.encode(payload),
               let output = String(data: data, encoding: .utf8) {
                print(output)
            }
        } else {
            for result in results {
                print(result.usage.cliLine(status: result.status))
            }
        }
        return 0
    }

    private static func dumpProviderFilter(from args: [String]) -> String {
        for (index, arg) in args.enumerated() {
            if arg == "--provider", index + 1 < args.count {
                return args[index + 1].lowercased()
            }
            if arg.hasPrefix("--provider=") {
                return String(arg.dropFirst("--provider=".count)).lowercased()
            }
        }
        return "all"
    }
}

private struct DumpProvider: Codable {
    struct Window: Codable {
        let label: String
        let usedPercent: Double
        let remainingPercent: Double
        let resetsAt: Date?
    }

    struct Status: Codable {
        let providerName: String
        let level: String
        let detail: String?
        let updatedAt: Date?
    }

    let provider: String
    let state: String
    let plan: String?
    let stale: Bool
    let windows: [Window]
    let status: Status?

    init(usage: ProviderUsage, status serviceStatus: ServiceStatus?) {
        provider = usage.name
        state = usage.state.dumpName
        plan = usage.plan
        stale = usage.stale
        windows = usage.windows.map {
            Window(
                label: $0.label,
                usedPercent: $0.usedPercent,
                remainingPercent: max(0, min(100, 100 - $0.usedPercent)),
                resetsAt: $0.resetsAt
            )
        }
        status = serviceStatus.map {
            Status(
                providerName: $0.providerName,
                level: $0.level.rawValue,
                detail: $0.detail,
                updatedAt: $0.updatedAt
            )
        }
    }
}
