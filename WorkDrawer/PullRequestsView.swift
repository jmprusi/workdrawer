//
//  PullRequestsView.swift
//  WorkDrawer
//
//  Created by Joaquim Moreno Prusi on 1/7/26.
//

import SwiftUI
import Combine

struct GitHubPullRequest: Codable, Identifiable {
    struct Repository: Codable {
        let nameWithOwner: String
    }

    enum CheckStatus: String, Codable {
        case success = "SUCCESS"
        case failure = "FAILURE"
        case error = "ERROR"
        case pending = "PENDING"
        case expected = "EXPECTED"

        var symbolName: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .failure, .error: return "xmark.circle.fill"
            case .pending, .expected: return "clock.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .failure, .error: return .red
            case .pending, .expected: return .orange
            }
        }

        var label: String {
            switch self {
            case .success: return "Checks passed"
            case .failure, .error: return "Checks failed"
            case .pending, .expected: return "Checks running"
            }
        }
    }

    let number: Int
    let title: String
    let url: String
    let state: String
    let isDraft: Bool
    let updatedAt: String
    let commentsCount: Int
    let repository: Repository
    var checkStatus: CheckStatus? = nil

    var id: String { url }

    var displayStatus: String {
        if state == "open" && isDraft { return "Draft" }
        switch state {
        case "open": return "Open"
        case "merged": return "Merged"
        default: return "Closed"
        }
    }

    var statusColor: Color {
        switch displayStatus {
        case "Open": return .green
        case "Merged": return .purple
        case "Draft": return .secondary
        default: return .red
        }
    }

    var updatedRelative: String? {
        guard let date = ISO8601DateFormatter().date(from: updatedAt) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

enum GitHubCLIError: LocalizedError {
    case notFound
    case notAuthenticated(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "GitHub CLI (gh) not found."
        case .notAuthenticated(let message):
            return message
        case .commandFailed(let message):
            return message
        }
    }
}

nonisolated struct GitHubCLI {
    private static let candidatePaths = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh"
    ]

    private func resolveExecutablePath() -> String? {
        Self.candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func fetchPullRequests(scopeFlag: String, showClosed: Bool, owners: [String]) throws -> [GitHubPullRequest] {
        var arguments = [
            "search", "prs", scopeFlag,
            "--json", "number,title,url,state,isDraft,updatedAt,commentsCount,repository",
            "--limit", "30",
            "--sort", "updated"
        ]
        if !showClosed {
            arguments += ["--state", "open"]
        }
        for owner in owners {
            arguments += ["--owner", owner]
        }

        let outputData = try run(arguments: arguments)

        return try JSONDecoder().decode([GitHubPullRequest].self, from: outputData)
    }

    func fetchCheckStatuses(for prs: [GitHubPullRequest]) throws -> [String: GitHubPullRequest.CheckStatus] {
        let allowedNamePart = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")

        var seenKeys = Set<String>()
        var items: [(key: String, owner: String, name: String, number: Int)] = []
        for pr in prs {
            let key = "\(pr.repository.nameWithOwner)#\(pr.number)"
            guard seenKeys.insert(key).inserted else { continue }
            let parts = pr.repository.nameWithOwner.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  parts[0].unicodeScalars.allSatisfy(allowedNamePart.contains),
                  parts[1].unicodeScalars.allSatisfy(allowedNamePart.contains) else { continue }
            items.append((key: key, owner: parts[0], name: parts[1], number: pr.number))
        }
        guard !items.isEmpty else { return [:] }

        let fields = items.enumerated().map { index, item in
            """
            p\(index): repository(owner: "\(item.owner)", name: "\(item.name)") {
              pullRequest(number: \(item.number)) {
                commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
              }
            }
            """
        }.joined(separator: "\n")
        let query = "query {\n\(fields)\n}"

        let outputData = try run(arguments: ["api", "graphql", "-f", "query=\(query)"])

        guard let json = try JSONSerialization.jsonObject(with: outputData) as? [String: Any],
              let data = json["data"] as? [String: Any] else {
            return [:]
        }

        var results: [String: GitHubPullRequest.CheckStatus] = [:]
        for (index, item) in items.enumerated() {
            guard let alias = data["p\(index)"] as? [String: Any],
                  let pullRequest = alias["pullRequest"] as? [String: Any],
                  let commits = pullRequest["commits"] as? [String: Any],
                  let nodes = commits["nodes"] as? [[String: Any]],
                  let commit = nodes.first?["commit"] as? [String: Any],
                  let rollup = commit["statusCheckRollup"] as? [String: Any],
                  let state = rollup["state"] as? String,
                  let status = GitHubPullRequest.CheckStatus(rawValue: state) else { continue }
            results[item.key] = status
        }
        return results
    }

    private func run(arguments: [String]) throws -> Data {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        if let ghPath = resolveExecutablePath() {
            process.executableURL = URL(fileURLWithPath: ghPath)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh"] + arguments
        }

        do {
            try process.run()
        } catch {
            throw GitHubCLIError.notFound
        }

        // Drain both pipes while gh runs: either can exceed the pipe buffer.
        let errorOutput = ErrorOutput()
        let errorReader = DispatchGroup()
        errorReader.enter()
        DispatchQueue.global(qos: .utility).async {
            errorOutput.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            errorReader.leave()
        }
        let outputData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        errorReader.wait()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorOutput.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationStatus == 127 || message.localizedCaseInsensitiveContains("no such file or directory") {
                throw GitHubCLIError.notFound
            }
            if message.localizedCaseInsensitiveContains("auth login") {
                throw GitHubCLIError.notAuthenticated(message)
            }
            throw GitHubCLIError.commandFailed(message.isEmpty ? "gh exited with status \(process.terminationStatus)" : message)
        }
        return outputData
    }

    // Written only by the error reader and read after its DispatchGroup completes.
    private final class ErrorOutput: @unchecked Sendable {
        var data = Data()
    }
}

private struct PullRequestCache: Codable {
    let authored: [GitHubPullRequest]
    let involving: [GitHubPullRequest]
    let showClosed: Bool
    let orgFilter: String
    let lastUpdated: Date
}

@MainActor
final class PullRequestStore: ObservableObject {
    static let shared = PullRequestStore()

    @Published var authored: [GitHubPullRequest] = []
    @Published var involving: [GitHubPullRequest] = []
    @Published var showClosed = false
    @Published var orgFilter = ""
    @Published var isLoading = false
    @Published var cliError: GitHubCLIError?
    @Published var lastUpdated: Date?

    private let cli = GitHubCLI()
    private let refreshInterval: TimeInterval = 5 * 60
    private let cacheKey = "cachedPullRequests"
    private var timer: Timer?

    private init() {
        loadCache()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        if lastUpdated.map({ Date().timeIntervalSince($0) >= refreshInterval }) ?? true {
            refresh()
        }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        cliError = nil
        let showClosed = showClosed
        let owners = orgFilter
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)

        Task.detached(priority: .userInitiated) {
            do {
                var authored = try self.cli.fetchPullRequests(scopeFlag: "--author=@me", showClosed: showClosed, owners: owners)
                var involving = try self.cli.fetchPullRequests(scopeFlag: "--involves=@me", showClosed: showClosed, owners: owners)

                if let statuses = try? self.cli.fetchCheckStatuses(for: authored + involving) {
                    for i in authored.indices {
                        authored[i].checkStatus = statuses["\(authored[i].repository.nameWithOwner)#\(authored[i].number)"]
                    }
                    for i in involving.indices {
                        involving[i].checkStatus = statuses["\(involving[i].repository.nameWithOwner)#\(involving[i].number)"]
                    }
                }

                let finalAuthored = authored
                let finalInvolving = involving
                await MainActor.run {
                    self.authored = finalAuthored
                    self.involving = finalInvolving
                    self.isLoading = false
                    self.lastUpdated = Date()
                    self.saveCache()
                }
            } catch let cliError as GitHubCLIError {
                await MainActor.run {
                    self.cliError = cliError
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.cliError = .commandFailed(error.localizedDescription)
                    self.isLoading = false
                }
            }
        }
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode(PullRequestCache.self, from: data) else { return }
        authored = cache.authored
        involving = cache.involving
        showClosed = cache.showClosed
        orgFilter = cache.orgFilter
        lastUpdated = cache.lastUpdated
    }

    private func saveCache() {
        let cache = PullRequestCache(authored: authored, involving: involving, showClosed: showClosed, orgFilter: orgFilter, lastUpdated: lastUpdated ?? Date())
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

func resolvedAppFont(baseSize: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, prefs: FontPreferences) -> Font {
    let size = max(8, baseSize + (prefs.fontSize - 14))
    if prefs.fontFamily.isEmpty {
        return .system(size: size, weight: weight, design: design)
    }
    return .custom(prefs.fontFamily, size: size).weight(weight)
}

struct PullRequestsView: View {
    @StateObject private var store = PullRequestStore.shared
    @StateObject private var fontPrefs = FontPreferences.shared

    private func appFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        resolvedAppFont(baseSize: size, weight: weight, design: design, prefs: fontPrefs)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let cliError = store.cliError {
                errorView(cliError)
            } else {
                List {
                    Section("Authored by You") {
                        if store.authored.isEmpty && !store.isLoading {
                            Text("No pull requests").foregroundColor(.secondary)
                        }
                        ForEach(store.authored) { pr in
                            PullRequestRow(pr: pr)
                        }
                    }

                    Section("Involving You") {
                        if store.involving.isEmpty && !store.isLoading {
                            Text("No pull requests").foregroundColor(.secondary)
                        }
                        ForEach(store.involving) { pr in
                            PullRequestRow(pr: pr)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .border(Color.gray.opacity(0.3), width: 1)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("Pull Requests")
                    .font(appFont(13, weight: .semibold))

                Spacer()

                if let lastUpdated = store.lastUpdated {
                    Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                        .font(appFont(10))
                        .foregroundColor(.secondary)
                }

                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: { store.refresh() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh")
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "building.2")
                    .font(appFont(11))
                    .foregroundColor(.secondary)

                TextField("Filter owners (comma-separated)", text: $store.orgFilter)
                    .textFieldStyle(.plain)
                    .font(appFont(12))
                    .onSubmit {
                        store.refresh()
                    }

                if !store.orgFilter.isEmpty {
                    Button(action: {
                        store.orgFilter = ""
                        store.refresh()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Toggle("Show closed/merged", isOn: $store.showClosed)
                    .toggleStyle(.checkbox)
                    .font(appFont(12))
                    .onChange(of: store.showClosed) { _, _ in
                        store.refresh()
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func errorView(_ error: GitHubCLIError) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(title(for: error))
                        .font(appFont(13, weight: .semibold))
                }

                switch error {
                case .notFound:
                    Text("WorkDrawer uses the GitHub CLI (gh) to fetch your pull requests, but it isn't installed (or couldn't be found in the usual Homebrew locations).")
                        .font(appFont(12))
                        .foregroundColor(.secondary)

                    commandBlock(label: "1. Install the GitHub CLI", command: "brew install gh")
                    commandBlock(label: "2. Log in to your GitHub account", command: "gh auth login")

                case .notAuthenticated:
                    Text("gh is installed, but it looks like you're not logged in yet.")
                        .font(appFont(12))
                        .foregroundColor(.secondary)

                    commandBlock(label: "Log in to your GitHub account", command: "gh auth login")

                case .commandFailed(let message):
                    Text(message)
                        .font(appFont(12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                Button("Retry") { store.refresh() }
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func title(for error: GitHubCLIError) -> String {
        switch error {
        case .notFound: return "GitHub CLI not found"
        case .notAuthenticated: return "Not logged in to GitHub"
        case .commandFailed: return "Couldn't load pull requests"
        }
    }

    private func commandBlock(label: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(appFont(11, weight: .medium))
                .foregroundColor(.secondary)
            HStack {
                Text(command)
                    .font(appFont(12, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button(action: { copyToClipboard(command) }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy")
            }
            .padding(6)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(4)
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct PullRequestRow: View {
    let pr: GitHubPullRequest
    @StateObject private var fontPrefs = FontPreferences.shared

    private func appFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        resolvedAppFont(baseSize: size, weight: weight, design: design, prefs: fontPrefs)
    }

    var body: some View {
        Button(action: openURL) {
            HStack(spacing: 10) {
                Circle()
                    .fill(pr.statusColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.title)
                        .font(appFont(13))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(appFont(11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if pr.commentsCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "bubble.left")
                        Text("\(pr.commentsCount)")
                    }
                    .font(appFont(11))
                    .foregroundColor(.secondary)
                    .help("\(pr.commentsCount) comment\(pr.commentsCount == 1 ? "" : "s")")
                }

                if let checkStatus = pr.checkStatus {
                    Image(systemName: checkStatus.symbolName)
                        .font(appFont(12))
                        .foregroundColor(checkStatus.color)
                        .help(checkStatus.label)
                }

                Image(systemName: "arrow.up.forward.square")
                    .font(appFont(11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy Link") { copyURLToClipboard() }
        }
    }

    private var subtitle: String {
        var parts = ["\(pr.repository.nameWithOwner) #\(pr.number)", pr.displayStatus]
        if let relative = pr.updatedRelative {
            parts.append(relative)
        }
        return parts.joined(separator: " · ")
    }

    private func openURL() {
        guard let url = URL(string: pr.url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyURLToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pr.url, forType: .string)
    }
}
