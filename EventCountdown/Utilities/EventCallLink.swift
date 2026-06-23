import Foundation

enum EventCallLink {
    static func resolve(eventURL: URL?, location: String?, notes: String?) -> URL? {
        if let eventURL, isCallURL(eventURL) {
            return normalizedCallURL(eventURL)
        }

        for text in [location, notes].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            if let url = firstCallLink(in: text) {
                return url
            }
        }
        return nil
    }

    private static let callHostSuffixes = [
        "zoom.us",
        "zoom.com",
        "meet.google.com",
        "hangouts.google.com",
        "teams.microsoft.com",
        "teams.live.com",
        "webex.com",
        "gotomeet.me",
        "gotomeeting.com",
        "whereby.com",
        "bluejeans.com",
        "chime.aws",
        "join.skype.com",
        "meet.jit.si",
        "duo.google.com",
        "facetime.apple.com",
    ]

    private static let excludedHostSuffixes = [
        "maps.apple.com",
        "maps.google.com",
        "goo.gl",
    ]

    private static func isCallURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "tel" || scheme == "facetime" || scheme == "facetime-audio" {
            return true
        }
        guard scheme == "http" || scheme == "https" else { return false }
        guard let host = url.host?.lowercased() else { return false }
        if excludedHostSuffixes.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return false
        }
        return callHostSuffixes.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private static func normalizedCallURL(_ url: URL) -> URL {
        if url.scheme?.lowercased() == "tel" {
            return url
        }
        return url
    }

    private static func firstCallLink(in text: String) -> URL? {
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)

        for match in matches {
            if match.resultType == .link, let url = match.url, isCallURL(url) {
                return normalizedCallURL(url)
            }
            if match.resultType == .phoneNumber, let number = match.phoneNumber {
                let digits = number.filter { $0.isNumber || $0 == "+" }
                guard digits.count >= 7, let url = URL(string: "tel:\(digits)") else { continue }
                return url
            }
        }
        return nil
    }
}
