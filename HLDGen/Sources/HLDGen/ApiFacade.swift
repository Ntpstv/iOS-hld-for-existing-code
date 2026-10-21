import Foundation

/// A second common API shape, where one facade object carries every call and a single route enum
/// holds every path:
///
///     // a ViewModel, in a folder of its own
///     AppEnvironment.current.apiService.fetchUserSelf()
///     // the facade
///     func fetchUserSelf() -> … { return request(.userSelf) }
///     // the route enum
///     case .userSelf: return (.GET, "/v1/users/self", [:], nil)
///
/// None of it sits in the screen's folder: the screen only names its ViewModel. So the index is
/// built repo-wide and joined per screen by `facadeEndpoints(forSceneAt:index:)`.
struct FacadeIndex {
    /// facade method name → route case it requests
    var methodToRoute: [String: String] = [:]
    /// route case → endpoint
    var routes: [String: ApiEndpoint] = [:]
    /// ViewModel class name → its source
    var viewModels: [String: String] = [:]

    var isEmpty: Bool { methodToRoute.isEmpty || routes.isEmpty }
}

func buildFacadeIndex(scanRoots: [URL]) -> FacadeIndex {
    var index = FacadeIndex()
    for root in scanRoots {
        for file in findFiles(under: root, extensions: ["swift"]) {
            let path = file.path
            guard !path.contains("/.build/"), !path.contains("Tests/") else { continue }
            let src = readFile(file)

            if src.contains("enum Route") { parseRouteEnum(src, into: &index) }

            // The facade: functions whose body requests a route case, `request(.userSelf)`.
            if src.contains("ServiceType") || src.contains("func request") {
                for fn in extractFunctionBodies(src) where index.methodToRoute[fn.name] == nil {
                    if let m = fn.body.firstMatch(#"\brequest\w*\(\s*(?:Route)?\.(\w+)"#) {
                        index.methodToRoute[fn.name] = m[1]
                    }
                }
            }

            for m in src.matches(#"class\s+([A-Z]\w*ViewModel)\b"#) where index.viewModels[m[1]] == nil {
                index.viewModels[m[1]] = src
            }
        }
    }
    return index
}

/// Route arms of the form `case let .name(…): … return (.GET, "/v1/path/\(id)", …)`.
private func parseRouteEnum(_ src: String, into index: inout FacadeIndex) {
    // Arms are cut apart first and each searched on its own. Matching a whole arm with one
    // non-greedy pattern ran past an arm whose path is computed (`statsURL?.absoluteString`) and
    // took the next arm's literal instead — reporting a video-stats call as the login endpoint.
    let starts = src.matchesWithRange(#"\n\s*case\s+(?:let\s+)?\.(\w+)\b"#)
    for (i, start) in starts.enumerated() {
        let name = start.groups[1]
        guard index.routes[name] == nil else { continue }
        let end = i + 1 < starts.count ? starts[i + 1].start : src.endIndex
        let arm = String(src[start.start..<end])

        guard let ret = arm.firstMatch(#"return\s*\(\s*\.(\w+)\s*,\s*([^,]+)"#,
                                       options: [.dotMatchesLineSeparators]) else { continue }
        let method = ret[1].uppercased()
        let pathExpr = ret[2].trimmingCharacters(in: .whitespacesAndNewlines)

        let path: String
        if let literal = pathExpr.firstMatch(#"^"((?:[^"\\]|\\.)*)""#) {
            // Interpolated segments are runtime values; a placeholder keeps the path readable.
            path = literal[1].replacingOccurrences(of: #"\\\([^)]*\)+"#, with: "{…}",
                                                   options: .regularExpression)
        } else if let suffix = arm.firstMatch(#"appendingPathComponent\(\s*"([^"]+)""#) {
            // Built at runtime from a base URL plus a fixed suffix: show the part that is known.
            path = "{…}/" + suffix[1]
        } else {
            continue   // no knowable path — leave it unresolved rather than guess
        }
        index.routes[name] = ApiEndpoint(caseName: name, path: path, method: method)
    }
}

/// Endpoints a screen reaches through its ViewModel's calls on the facade.
func facadeEndpoints(forSceneAt sceneDir: URL, index: FacadeIndex) -> [ApiEndpoint] {
    guard !index.isEmpty else { return [] }
    var sources = findSceneFiles(under: sceneDir, extensions: ["swift"]).map(readFile)

    // `let viewModel: FooViewModelType = FooViewModel()` — the ViewModel lives elsewhere.
    var named = Set<String>()
    for src in sources {
        for m in src.matches(#"\b([A-Z]\w*ViewModel)(?:Type)?\b"#) { named.insert(m[1]) }
    }
    sources += named.compactMap { index.viewModels[$0] }

    var endpoints: [ApiEndpoint] = []
    var seen = Set<String>()
    for src in sources {
        for m in src.matches(#"\bapiService\.(\w+)\s*\("#) {
            guard let route = index.methodToRoute[m[1]], var endpoint = index.routes[route] else { continue }
            guard seen.insert("\(endpoint.method) \(endpoint.path)").inserted else { continue }
            endpoint.service = "apiService.\(m[1])"
            endpoints.append(endpoint)
        }
    }
    return endpoints
}
