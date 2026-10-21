import Foundation

/// A scene calls a service, but the path and HTTP method live two hops away, usually in a
/// different framework entirely:
///
///     // a shared services framework
///     class ProfileHomeService: BaseService<ProfileHomeAPI, ProfileHomeRequest, ProfileHomeResponse>
///     class ProfileHomeAPI: BaseAPI<…> { … Router.profileHome(parameters:) … }
///     // a shared data-repository framework
///     enum Router { case profileHome; var path: String { "/api/v1/…" } }
///
/// Resolving only the first hop, inside the module's own API folder, finds nothing: the module's
/// router is not the one its services reach. So the scan is repo-wide and the join is keyed by
/// `RouterType.caseName` — two routers in a large app routinely share a case name.
struct ServiceBinding {
    var api: String
    var requestType: String
    var responseType: String
}

/// Joins every layer into the lookup the analysers use: service class name → endpoint.
/// One walk, reading each file once — four separate passes over a 15,000-file repo is four times
/// the I/O for the same answer.
func resolveServiceEndpoints(scanRoots: [URL]) -> [String: ApiEndpoint] {
    var endpoints: [String: ApiEndpoint] = [:]   // "RouterType.caseName" → endpoint
    var bindings:  [String: ServiceBinding] = [:]
    var apiCalls:  [String: String] = [:]        // api class → "RouterType.caseName"
    var models:    [String: ModelDef] = [:]
    // A `struct Foo { static func … { BarService().execute() } }` is a service to its callers but
    // has no generic binding of its own; remember what each such type instantiates.
    var wrappers:  [String: [String]] = [:]

    for root in scanRoots {
        for file in findFiles(under: root, extensions: ["swift"]) {
            let src = readFile(file)

            if file.lastPathComponent.hasSuffix("Router.swift") {
                let routerType = src.firstMatch(#"(?:enum|struct|class)\s+(\w*Router)\b"#)?[1]
                    ?? file.deletingPathExtension().lastPathComponent
                for endpoint in parseApiRouterFile(file) {
                    let key = "\(routerType).\(endpoint.caseName)"
                    if endpoints[key] == nil { endpoints[key] = endpoint }
                }
            }

            // Any generic base is accepted, not one framework's `BaseService`: what identifies
            // the layer is a `*Service` class parameterised by <API, Request, Response>.
            if src.contains("Service") && src.contains("<") {
                // `\w*Service\w*`, not `\w*Service`: versioned classes such as
                // `FooServiceV2` are the same layer and were being skipped.
                for m in src.matches(#"class\s+(\w*Service\w*)\s*:\s*\w+\s*<([^>]+)>"#) {
                    let args = m[2].split(separator: ",").map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    guard args.count >= 3 else { continue }
                    bindings[m[1]] = ServiceBinding(api: args[0],
                                                    requestType: args[1],
                                                    responseType: args[2])
                }
            }

            if src.contains("Router."),
               let decl = src.firstMatch(#"(?:class|struct|enum)\s+(\w+)"#),
               let call = findRouterCall(in: src) {
                apiCalls[decl[1]] = "\(call.router).\(call.caseName)"
            }

            if let decl = src.firstMatch(#"(?:struct|enum|final class|class)\s+(\w*Service)\b"#) {
                let owner = decl[1]
                let inner = src.matches(#"\b(\w+Service)\s*\("#).map { $0[1] }.filter { $0 != owner }
                if !inner.isEmpty { wrappers[owner, default: []].append(contentsOf: inner) }
            }

            for (name, def) in parseModels(in: src) where models[name] == nil {
                models[name] = def
            }
        }
    }

    var resolved: [String: ApiEndpoint] = [:]
    for (service, binding) in bindings {
        guard let key = apiCalls[binding.api],
              var endpoint = endpoints[key] else { continue }
        endpoint.service       = service
        endpoint.requestType   = binding.requestType
        endpoint.responseType  = binding.responseType
        endpoint.requestFields  = fieldsFor(binding.requestType, in: models)
        endpoint.responseFields = fieldsFor(binding.responseType, in: models)
        resolved[service] = endpoint
    }

    // Types that reach the router directly, with no separate API class in between.
    for (type, key) in apiCalls where resolved[type] == nil {
        guard var endpoint = endpoints[key] else { continue }
        endpoint.service = type
        resolved[type] = endpoint
    }

    // A wrapper takes the endpoint of the service it delegates to, so callers that only ever see
    // the wrapper still resolve.
    for (owner, inner) in wrappers where resolved[owner] == nil {
        guard let hit = inner.first(where: { resolved[$0] != nil }), var endpoint = resolved[hit] else { continue }
        endpoint.service = owner
        resolved[owner] = endpoint
    }

    FileHandle.standardError.write("""
    api graph: \(endpoints.count) router cases · \(bindings.count) services · \
    \(apiCalls.count) api classes → \(resolved.count) endpoints resolved

    """.data(using: .utf8)!)
    return resolved
}
