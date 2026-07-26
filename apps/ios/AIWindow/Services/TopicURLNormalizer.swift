import Foundation

enum TopicURLNormalizer {
    static func canonicalTopicURL(from url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == defaultPort(for: scheme),
              normalizedHost(of: url) == "linux.do"
        else {
            return nil
        }

        let segments = url.pathComponents.filter { $0 != "/" }
        guard segments.first?.lowercased() == "t" else {
            return nil
        }

        let topicIDIndex: Int
        if segments.count >= 2, isPositiveInteger(segments[1]) {
            topicIDIndex = 1
        } else if segments.count >= 3, isPositiveInteger(segments[2]) {
            topicIDIndex = 2
        } else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "linux.do"
        components.path = "/" + segments[...topicIDIndex].joined(separator: "/")
        return components.url
    }

    static func isLinuxDOURL(_ url: URL) -> Bool {
        normalizedHost(of: url) == "linux.do"
    }

    static func isAllowedInAppHost(_ url: URL) -> Bool {
        guard let host = normalizedHost(of: url) else { return false }
        return host == "linux.do"
            || host == "google.com"
            || host.hasSuffix(".google.com")
            || host == "bing.com"
            || host.hasSuffix(".bing.com")
    }

    static func isAllowedInAppURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "https"
            && url.user == nil
            && url.password == nil
            && (url.port == nil || url.port == defaultPort(for: scheme))
            && isAllowedInAppHost(url)
    }

    static func isSafeExternalURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "http", "https":
            return url.host?.isEmpty == false
                && url.user == nil
                && url.password == nil
        case "mailto", "tel":
            return true
        default:
            return false
        }
    }

    private static func normalizedHost(of url: URL) -> String? {
        url.host?
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .replacingOccurrences(of: "www.", with: "", options: [.anchored])
    }

    private static func defaultPort(for scheme: String?) -> Int? {
        switch scheme {
        case "http": 80
        case "https": 443
        default: nil
        }
    }

    private static func isPositiveInteger(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.allSatisfy({ (48...57).contains($0) }) else {
            return false
        }
        return Int(value).map { $0 > 0 } == true
    }
}
