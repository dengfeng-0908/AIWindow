import Foundation

enum SearchEngine: String, CaseIterable, Codable, Identifiable {
    case linuxDO
    case bing
    case google

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .linuxDO:
            "LINUX DO"
        case .bing:
            "Bing"
        case .google:
            "Google"
        }
    }

    var host: String {
        switch self {
        case .linuxDO:
            "linux.do"
        case .bing:
            "www.bing.com"
        case .google:
            "www.google.com"
        }
    }

    func searchURL(for query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/search"
        switch self {
        case .linuxDO:
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        case .bing, .google:
            components.queryItems = [
                URLQueryItem(name: "q", value: "site:linux.do/t/topic \(query)"),
            ]
        }
        return components.url
    }
}
