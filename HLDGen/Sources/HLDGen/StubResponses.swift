import Foundation

/// Example responses taken from the project's own stub server, so the HLD shows a real payload
/// rather than an invented one. The mapping file lists a URL and the JSON returned for it:
///
///     - request:
///          method: POST
///          url: /api/v1/profile/v3/home
///       response:
///          status: 200
///          file: TestCases/Home/profile_home.json
///
/// Endpoints with no stub keep their field list and show no example — a fabricated payload on an
/// HLD would be read as fact.
func loadStubResponses(mappingFile: URL) -> [String: String] {
    let src = readFile(mappingFile)
    guard !src.isEmpty else { return [:] }
    let root = mappingFile.deletingLastPathComponent()

    var byURL: [String: String] = [:]
    for m in src.matches(#"url:\s*(\S+)[\s\S]*?file:\s*(\S+)"#) {
        let url = m[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        let file = m[2].trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        if byURL[url] == nil { byURL[url] = file }   // first entry wins, as the stub server does
    }

    var examples: [String: String] = [:]
    for (url, file) in byURL {
        let body = readFile(root.appendingPathComponent(file))
        guard !body.isEmpty else { continue }
        examples[url] = body
    }
    return examples
}

/// Stub URLs are sometimes the whole path and sometimes only its tail, so an endpoint matches
/// either exactly or by one being the suffix of the other.
func stubExample(for path: String, in examples: [String: String]) -> String? {
    if let exact = examples[path] { return exact }
    var best: (url: String, body: String)?
    for (url, body) in examples where url.count > 1 {
        guard path.hasSuffix(url) || url.hasSuffix(path) else { continue }
        if best == nil || url.count > best!.url.count { best = (url, body) }   // most specific wins
    }
    return best?.body
}

/// Compacts a JSON payload onto a handful of lines: the response's own fields, one per line,
/// with nested objects and arrays summarised rather than expanded.
func summariseJSON(_ raw: String, maxFields: Int = 10) -> [String] {
    guard let data = raw.data(using: .utf8),
          let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [] }

    // The payload worth showing sits under `content`; the envelope around it is the same every time.
    let body = (top["content"] as? [String: Any]) ?? top
    var lines: [String] = []
    for key in body.keys.sorted() {
        if lines.count == maxFields { lines.append("…"); break }
        lines.append("\(key): \(describe(body[key]!))")
    }
    return lines
}

private func describe(_ value: Any) -> String {
    switch value {
    case is NSNull: return "null"
    case let s as String: return s.isEmpty ? "\"\"" : "\"\(s.prefix(28))\(s.count > 28 ? "…" : "")\""
    case let b as Bool where type(of: value) == type(of: NSNumber(value: true)): return b ? "true" : "false"
    case let n as NSNumber: return n.stringValue
    case let a as [Any]:
        guard let first = a.first else { return "[]" }
        return a.count == 1 ? "[\(describe(first))]" : "[\(describe(first)), … \(a.count) items]"
    case let d as [String: Any]:
        let keys = d.keys.sorted().prefix(3).joined(separator: ", ")
        return "{ \(keys)\(d.count > 3 ? ", …" : "") }"
    default: return "\(value)"
    }
}
