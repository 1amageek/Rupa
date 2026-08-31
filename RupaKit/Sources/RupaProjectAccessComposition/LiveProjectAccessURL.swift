import Foundation

func canonicalLiveProjectURL(_ url: URL) -> URL {
    url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
}

func canonicalLiveSessionPath(_ path: String?) throws -> URL? {
    guard let path, !path.isEmpty else {
        return nil
    }
    guard path.hasPrefix("/"), !path.contains("\0") else {
        throw LiveProjectAccessError.invalidSessionPath(path)
    }
    return canonicalLiveProjectURL(URL(fileURLWithPath: path))
}
