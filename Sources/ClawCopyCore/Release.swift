import Foundation

/// A release version such as "0.1.42" (an optional leading "v" is accepted).
public struct ReleaseVersion: Comparable, Sendable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ string: String) {
        var text = Substring(string)
        if text.hasPrefix("v") { text = text.dropFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var components: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 9, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part) else { return nil }
            components.append(number)
        }
        self.components = components
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    /// Missing components count as 0, so "1.2" == "1.2.0".
    private static func compare(_ a: ReleaseVersion, _ b: ReleaseVersion) -> Int {
        for i in 0..<max(a.components.count, b.components.count) {
            let x = i < a.components.count ? a.components[i] : 0
            let y = i < b.components.count ? b.components[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    public static func < (a: ReleaseVersion, b: ReleaseVersion) -> Bool { compare(a, b) < 0 }
    public static func == (a: ReleaseVersion, b: ReleaseVersion) -> Bool { compare(a, b) == 0 }
}

/// The latest release, as read from GitHub's "latest release" API response.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: ReleaseVersion
    /// The release's page on GitHub, where it can be downloaded.
    public let pageURL: URL

    public static let maxResponseBytes = 1_000_000

    /// Parses and strictly validates the API response. Only the version tag and the release
    /// page URL are read, and the URL must be an https page under `releasesPagePrefix`
    /// (this repository's releases), so the app can never be pointed anywhere else.
    public static func parse(_ data: Data, releasesPagePrefix: String) -> ReleaseInfo? {
        guard data.count <= maxResponseBytes else { return nil }
        struct Payload: Decodable {
            let tag_name: String
            let html_url: String
            let draft: Bool?
            let prerelease: Bool?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true,
              let version = ReleaseVersion(payload.tag_name),
              payload.html_url.hasPrefix(releasesPagePrefix),
              !payload.html_url.contains(".."),
              payload.html_url.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 0x20 && $0.value < 0x7F }),
              let url = URL(string: payload.html_url),
              url.scheme == "https" else { return nil }
        return ReleaseInfo(version: version, pageURL: url)
    }
}
