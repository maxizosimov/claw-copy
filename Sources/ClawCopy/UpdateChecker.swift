import AppKit
import ClawCopyCore

/// Checks GitHub for a newer release of Claw Copy.
///
/// This is the app's only network access, and it is deliberately narrow (`check-security.sh`
/// enforces it): one HTTPS GET to GitHub's "latest release" API for this repository, at most
/// daily, only in release builds, and only while "Check for Updates Automatically" is on (or
/// when the user clicks Check for Updates…). Nothing about the user or their clipboard is sent,
/// no cookies or cache are kept, redirects are refused, and only the version and the release
/// page link are read from the response. The app never downloads or runs anything: an update
/// opens the release page in the browser.
@MainActor
final class UpdateChecker {
    private static let latestReleaseAPI = "https://api.github.com/repos/maxizosimov/claw-copy/releases/latest"
    private static let releasesPagePrefix = "https://github.com/maxizosimov/claw-copy/releases/"
    private static let autoCheckKey = "checkForUpdatesAutomatically"
    private static let firstCheckDelayNanoseconds: UInt64 = 10_000_000_000
    private static let checkIntervalNanoseconds: UInt64 = 24 * 60 * 60 * 1_000_000_000

    enum Result {
        case updateAvailable(ReleaseInfo)
        case upToDate
        case failed
    }

    /// Set when a newer release than this build exists.
    private(set) var availableUpdate: ReleaseInfo?
    var onChange: (() -> Void)?

    /// Release builds come from the GitHub release workflow; local builds (build-app.sh,
    /// try.sh) are development builds and never check.
    let isReleaseBuild: Bool
    let currentVersion: ReleaseVersion?
    let commit: String?

    private var loop: Task<Void, Never>?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: configuration)
    }()

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        isReleaseBuild = info["ClawCopyReleaseBuild"] as? Bool ?? false
        currentVersion = (info["CFBundleShortVersionString"] as? String).flatMap(ReleaseVersion.init)
        commit = info["ClawCopyCommit"] as? String
        UserDefaults.standard.register(defaults: [Self.autoCheckKey: true])
    }

    /// e.g. "Version 0.1.42" or "Development build (8e36101)".
    var versionDescription: String {
        if isReleaseBuild, let currentVersion { return "Version \(currentVersion)" }
        return "Development build" + (commit.map { " (\($0.prefix(7)))" } ?? "")
    }

    var checksAutomatically: Bool {
        get { UserDefaults.standard.bool(forKey: Self.autoCheckKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.autoCheckKey)
            if newValue {
                start()
            } else {
                stop()
            }
        }
    }

    func start() {
        guard isReleaseBuild, checksAutomatically, loop == nil else { return }
        loop = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.firstCheckDelayNanoseconds)
            while !Task.isCancelled {
                _ = await self?.check()
                try? await Task.sleep(nanoseconds: Self.checkIntervalNanoseconds)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func check() async -> Result {
        guard isReleaseBuild, let currentVersion, let url = URL(string: Self.latestReleaseAPI) else { return .failed }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClawCopy", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request, delegate: RefuseRedirects())
        } catch {
            return .failed
        }
        let (data, response) = result
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let release = ReleaseInfo.parse(data, releasesPagePrefix: Self.releasesPagePrefix) else {
            return .failed
        }
        availableUpdate = release.version > currentVersion ? release : nil
        onChange?()
        return availableUpdate.map(Result.updateAvailable) ?? .upToDate
    }

    /// Opens the release page (validated to be this repository's releases on GitHub).
    func openReleasePage() {
        guard let page = availableUpdate?.pageURL else { return }
        NSWorkspace.shared.open(page)
    }
}

/// The request must be answered by the API host itself; any redirect is refused.
private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
