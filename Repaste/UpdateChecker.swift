import Foundation

/// Checks GitHub Releases for newer versions of Repaste.
@MainActor
final class UpdateChecker: ObservableObject {
    /// Change this to your actual GitHub repo (owner/repo).
    static let githubRepo = "kunalzed/repaste"

    @Published var latestVersion: String?
    @Published var releaseURL: URL?
    @Published var versionsBehind: Int = 0
    @Published var updateAvailable = false
    @Published var lastCheckFailed = false
    @Published var isChecking = false

    /// All release tag names fetched from GitHub, newest first.
    private var allTags: [String] = []

    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    func startPeriodicChecks() {
        check()
        // Re-check every 6 hours
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.check()
            }
        }
    }

    func check() {
        guard !isChecking else { return }
        isChecking = true
        lastCheckFailed = false

        let urlString = "https://api.github.com/repos/\(Self.githubRepo)/releases"
        guard let url = URL(string: urlString) else {
            isChecking = false
            lastCheckFailed = true
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isChecking = false

                guard error == nil,
                      let data,
                      let http = response as? HTTPURLResponse,
                      http.statusCode == 200
                else {
                    self.lastCheckFailed = true
                    return
                }

                self.parseReleases(data)
            }
        }.resume()
    }

    private func parseReleases(_ data: Data) {
        struct Release: Decodable {
            let tag_name: String
            let html_url: String
            let draft: Bool?
            let prerelease: Bool?
        }

        guard let releases = try? JSONDecoder().decode([Release].self, from: data) else {
            lastCheckFailed = true
            return
        }

        // Filter out drafts/prereleases, collect tags
        let published = releases.filter { !($0.draft ?? false) && !($0.prerelease ?? false) }
        guard !published.isEmpty else { return }

        allTags = published.map { Self.cleanTag($0.tag_name) }

        let latest = allTags[0]
        latestVersion = latest
        releaseURL = URL(string: published[0].html_url)

        let current = currentVersion
        if Self.isNewer(latest, than: current) {
            updateAvailable = true
            // Count how many versions behind
            if let currentIdx = allTags.firstIndex(of: current) {
                versionsBehind = currentIdx
            } else {
                // Current version not found in releases — count all that are newer
                versionsBehind = allTags.filter { Self.isNewer($0, than: current) }.count
            }
        } else {
            updateAvailable = false
            versionsBehind = 0
        }
    }

    /// Strip leading "v" from tags like "v1.2.0".
    private static func cleanTag(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Semantic version comparison: is `a` newer than `b`?
    private static func isNewer(_ a: String, than b: String) -> Bool {
        let ap = a.split(separator: ".").compactMap { Int($0) }
        let bp = b.split(separator: ".").compactMap { Int($0) }
        let len = max(ap.count, bp.count)
        for i in 0..<len {
            let av = i < ap.count ? ap[i] : 0
            let bv = i < bp.count ? bp[i] : 0
            if av > bv { return true }
            if av < bv { return false }
        }
        return false
    }
}
