# hldgen

A Swift static analyzer for iOS apps. Given one or more scene directories it produces a structured JSON
description of: each screen's components (ViewController/Interactor/Presenter/Router, or their MVC / MVVM /
SwiftUI equivalents), its storyboard/xib UI tree with real positions and labels parsed from the IB XML, its
navigation-bar title, every button/row/delegate action and where it leads, the NotificationCenter and local
storage calls it makes, and the backend endpoint behind each service call — path, HTTP method, request and
response fields, and a real example response when the project ships a stub server.

It exists so "explain this screen to a new engineer" doesn't require a human, or an LLM, to re-read and
re-trace the same Swift source every time. Run it, get ground-truth JSON, render whatever you like on top —
`../HLDFigmaPlugin` draws it as a Figma board.

## Build & run

```bash
swift build --package-path HLDGen
```

Most people should run `../hldgen.sh <ModuleDir>` instead: it finds every scene directory in the module, the
repo root to scan, the stub mapping and the flow file, then calls this. Use the analyzer directly only when
you want a subset of screens:

```bash
swift run --package-path HLDGen hldgen \
  MyModule/MyModule/Scenes/Home \
  MyModule/MyModule/Scenes/Checkout \
  --module MyModule \
  --services-dir . \
  -o bundle.json
```

Output is always an `HLDBundle` — `{ "module": "...", "scenes": [ <SceneResult>, ... ] }` — even for a single
scene. Paths are relative to wherever you run the command. Only `<sceneDir>` (one or more) and `--module` are
required; each other flag unlocks one more layer of resolution:

| Flag | Unlocks |
|---|---|
| *(none)* | Components, storyboard UI tree, action list, navigation title, notifications, local storage, and `router?.routeToX()` calls made directly in the screen. |
| `--services-dir` (repeatable) | The endpoint behind each service call: `class XService: BaseService<XAPI, Req, Res>` → the `Router.<case>` that `XAPI` calls → that case's path in any `*Router.swift` under the scanned roots, plus the request/response models' fields. Pass the repo root — those three layers usually sit in three different frameworks. Also the root for localised navigation titles. |
| `--flow-file` | Resolves actions that only emit an Output enum case (`onRouteNext.onNext(.X)`) to a real destination, by parsing the sibling `Flow/*.swift` coordinator's `switch model.caseOutput` and `showNext(type:)` calls. |
| `--stubs <run.yaml>` | A real example response per endpoint, taken from the project's stub server mapping. |
| `--lang <code>` | Which `.lproj` table wins when a title key exists in several languages. Defaults to `th`. |

`--api-dir` is accepted as a single scan root when no `--services-dir` is given; `--api-router` is accepted but
ignored — routers are discovered by the scan.

## What it understands

Architecture is detected per screen: CleanSwift/VIP, MVC, MVVM or SwiftUI. Across those it reads
`@IBAction`/`@objc` target-actions, RxSwift `.rx.tap` / `.rx.modelSelected(...)` / `.rx.controlEvent(...)`
bindings, plain delegate callbacks, service calls through a stored property, a local `let`/`var`, or inline
instantiation (`SomeService().execute(...)`), and up to three hops of same-file helper delegation.

API routers are read in both common shapes: one `static func` per endpoint, and an enum whose paths live in a
`switch` inside a computed property. Request and response models are read from ObjectMapper `mapping(map:)`
tables and from Codable `CodingKeys`.

## Known limitations

- **Regex and brace counting, not a real Swift parser.** Fast and dependency-free, but unusual formatting can
  fool it. When it cannot resolve something it leaves it unresolved rather than guessing.
- **Destinations are names, not types.** A flow case like `Confirm` is matched to a screen by name similarity,
  scored and thresholded. Below the threshold it stays unresolved — the renderer shows it as text instead of
  drawing a wrong link.
- **Payload fields are top level only.** A field whose type is another model shows the type name; the nested
  model is not expanded.
- **Example responses come only from a stub server mapping.** No stub for a path means no example: an invented
  payload on an HLD would be read as fact.
- **Titles drawn in a xib rather than set in code are not found.** Screens with no navigation bar are reported
  as such, so an empty title is distinguishable from a missed one.
