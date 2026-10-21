import Foundation

// MARK: - CLI

/// hldgen <sceneDir> [<sceneDir> ...] --module <name> [--api-dir <path>] [--api-router <path>] [--flow-file <path>] [-o <output.json>]
///
/// Accepts one or more scene directories. When more than one is supplied the output is an
/// HLDBundle ({ "module": "...", "scenes": [...] }) rather than a bare SceneResult — but
/// a single scene is also wrapped in HLDBundle, so the output shape is always the same.
///
/// Example (CalendarApp):
///   swift run --package-path Tools/HLDGen hldgen \
///     Calendar \
///     --module CalendarApp \
///     -o Tools/bundle.json

func printUsageAndExit() -> Never {
    FileHandle.standardError.write("""
    hldgen — CleanSwift/VIP scene analyzer for HLD generation

    Usage:
      hldgen <sceneDir> [<sceneDir> ...] --module <ModuleName>
             [--api-dir <path>] [--api-router <path>] [--flow-file <path>]
             [-o out.json]

    Output is always an HLDBundle:
      { "module": "...", "scenes": [ <SceneResult>, ... ] }

    Example:
      swift run --package-path Tools/HLDGen hldgen \\
        Calendar \\
        --module CalendarApp \\
        -o Tools/bundle.json

    """.data(using: .utf8)!)
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else { printUsageAndExit() }

var sceneDirArgs: [String] = []
var moduleName = "UnknownModule"
var apiDirArg: String?
var apiRouterArg: String?
var flowFileArg: String?
var outputArg: String?
/// Repeatable. Service classes usually live in a shared framework outside the module, so their
/// location cannot be derived from the scene paths.
var serviceDirArgs: [String] = []
/// Mapping file of the project's stub server, used for real response examples.
var stubsArg: String?
/// `.lproj` table preferred when a localisation key exists in several languages.
/// Left empty, the most-used `.lproj` in the scanned tree wins — the app's own language,
/// whatever it is.
var languageArg = ""

var i = 0
while i < args.count {
    switch args[i] {
    case "--module":   i += 1; if i < args.count { moduleName = args[i] }
    case "--api-dir":  i += 1; if i < args.count { apiDirArg = args[i] }
    case "--api-router": i += 1; if i < args.count { apiRouterArg = args[i] }
    case "--flow-file": i += 1; if i < args.count { flowFileArg = args[i] }
    case "--services-dir": i += 1; if i < args.count { serviceDirArgs.append(args[i]) }
    case "--stubs": i += 1; if i < args.count { stubsArg = args[i] }
    case "--lang": i += 1; if i < args.count { languageArg = args[i] }
    case "-o", "--output": i += 1; if i < args.count { outputArg = args[i] }
    default:
        // All non-flag positional args are treated as scene dirs
        if !args[i].hasPrefix("-") { sceneDirArgs.append(args[i]) }
    }
    i += 1
}

guard !sceneDirArgs.isEmpty else { printUsageAndExit() }

// MARK: - Resolve service-class -> endpoint

var serviceEndpoints: [String: ApiEndpoint] = [:]
let scanRoots = serviceDirArgs.isEmpty
    ? [apiDirArg].compactMap { $0 }.map { URL(fileURLWithPath: $0) }
    : serviceDirArgs.map { URL(fileURLWithPath: $0) }
if !scanRoots.isEmpty {
    serviceEndpoints = resolveServiceEndpoints(scanRoots: scanRoots)
}

if let stubsArg {
    let examples = loadStubResponses(mappingFile: URL(fileURLWithPath: stubsArg))
    var matched = 0
    for (service, endpoint) in serviceEndpoints {
        guard let body = stubExample(for: endpoint.path, in: examples) else { continue }
        let lines = summariseJSON(body)
        guard !lines.isEmpty else { continue }
        serviceEndpoints[service]?.responseExample = lines
        matched += 1
    }
    FileHandle.standardError.write(
        "stub responses: \(examples.count) urls → \(matched) endpoints with an example\n".data(using: .utf8)!)
}

var flowBindings: [FlowScreenBinding] = []
if let flowFileArg {
    flowBindings = parseFlowScreenBindings(readFile(URL(fileURLWithPath: flowFileArg)))
}

// MARK: - Analyze all scene dirs

/// The journey a scene belongs to: the folder directly beneath the container that holds all screens
/// (`Scenes/` by convention, `Screen/` in some projects). `Scenes/Checkout/Card/Confirm` and
/// `Scenes/Checkout/MainScreen` both return `Checkout`. Falls back to the parent folder, then the module.
func journeyGroup(for sceneDir: URL, module: String) -> String {
    let parts = sceneDir.pathComponents
    // Projects name this folder Scenes, Scene, Screens or Screen; match the shape, not one spelling.
    if let i = parts.lastIndex(where: { $0.range(of: #"^(?i)(scenes?|screens?)$"#, options: .regularExpression) != nil }),
       i + 1 < parts.count {
        return parts[i + 1]
    }
    let parent = sceneDir.deletingLastPathComponent().lastPathComponent
    return parent.isEmpty ? module : parent
}

// Titles arrive as localisation keys; the reader needs the words on screen.
let localizationRoot = scanRoots.first
    ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let language = languageArg.isEmpty ? dominantLanguage(under: localizationRoot) : languageArg
let localizations = loadLocalizations(under: localizationRoot, module: moduleName, language: language)

// The facade-and-route-enum API shape, resolved per screen through its ViewModel.
let facadeIndex = buildFacadeIndex(scanRoots: scanRoots)
if !facadeIndex.isEmpty {
    FileHandle.standardError.write(
        "api facade: \(facadeIndex.methodToRoute.count) facade methods · \(facadeIndex.routes.count) route cases · \(facadeIndex.viewModels.count) view models\n"
            .data(using: .utf8)!)
}

var scenes: [SceneResult] = []
for sceneDirPath in sceneDirArgs {
    let sceneDirURL = URL(fileURLWithPath: sceneDirPath)
    guard FileManager.default.fileExists(atPath: sceneDirURL.path) else {
        FileHandle.standardError.write("warning: scene directory not found, skipping: \(sceneDirPath)\n".data(using: .utf8)!)
        continue
    }
    // Feature-per-folder projects nest each screen in a role folder (`Login/Controller`,
    // `Comments/Controllers`). Named after that, 46 screens were all called "Controller" and every
    // connector between them collapsed into one; the feature folder above is the screen's name.
    let leaf = sceneDirURL.lastPathComponent
    let genericLeaf = leaf.range(of: #"^(?i)(controllers?|viewcontrollers?|views?|screens?|scenes?|ui|presentation)$"#,
                                 options: .regularExpression) != nil
    let sceneName = genericLeaf ? sceneDirURL.deletingLastPathComponent().lastPathComponent : leaf
    var result = analyzeScene(module: moduleName, sceneName: sceneName, sceneDir: sceneDirURL,
                              serviceEndpoints: serviceEndpoints, flowBindings: flowBindings)
    result.group = journeyGroup(for: sceneDirURL, module: moduleName)

    let facts = extractScreenFacts(sceneDir: sceneDirURL)
    result.navigationTitleKey = facts.titleKey
    result.navigationTitle = localizations[facts.titleKey] ?? facts.titleKey
    result.navigationBarHidden = facts.navBarHidden && facts.titleKey.isEmpty
    result.notifications = facts.notifications
    result.localStorage = facts.localStorage

    for endpoint in facadeEndpoints(forSceneAt: sceneDirURL, index: facadeIndex)
    where !result.apiEndpoints.contains(where: { $0.method == endpoint.method && $0.path == endpoint.path }) {
        result.apiEndpoints.append(endpoint)
    }
    scenes.append(result)
}

// Journeys come from folder names, which only works when a project groups related screens
// together (Scenes/Checkout/…). A feature-per-folder layout gives every screen its own journey,
// and since only same-journey moves are drawn as arrows, the board ends up with none at all.
// When most screens would sit alone, put them all in one journey named after their shared folder.
do {
    let sizes = Dictionary(grouping: scenes, by: \.group).mapValues(\.count)
    let alone = scenes.filter { sizes[$0.group] == 1 }.count
    if scenes.count > 3, Double(alone) / Double(scenes.count) > 0.6 {
        let paths = sceneDirArgs.map { URL(fileURLWithPath: $0).standardizedFileURL.pathComponents }
        var common = paths.first ?? []
        for p in paths.dropFirst() {
            common = Array(zip(common, p).prefix { $0.0 == $0.1 }.map(\.0))
        }
        let name = common.last.flatMap { $0 == "/" ? nil : $0 } ?? moduleName
        for i in scenes.indices { scenes[i].group = name }
        FileHandle.standardError.write(
            "journeys: \(alone) of \(scenes.count) screens were alone in their folder — grouped as '\(name)'\n"
                .data(using: .utf8)!)
    }
}

guard !scenes.isEmpty else {
    FileHandle.standardError.write("error: no valid scene directories found\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - Encode as HLDBundle

let bundle = HLDBundle(module: moduleName, scenes: scenes)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try! encoder.encode(bundle)

if let outputArg {
    try! data.write(to: URL(fileURLWithPath: outputArg))
    FileHandle.standardError.write("wrote \(scenes.count) scene(s) → \(outputArg)\n".data(using: .utf8)!)
} else {
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}
