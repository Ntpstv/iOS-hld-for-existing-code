# iOS-hld-for-existing-code

**English** | [ภาษาไทย](README.th.md)

- **iOS:** [github.com/Ntpstv/iOS-hld-for-existing-code](https://github.com/Ntpstv/iOS-hld-for-existing-code)
- **Android:** [github.com/opsst/android-hld-skill](https://github.com/opsst/android-hld-skill)
- **Slides (Mobile Native Thailand Meetup #4):** [Mobile Native 2026 #1.pdf](Mobile%20Native%202026%20%231.pdf)

Automated High-Level Design (HLD) generator for iOS projects.  
Analyzes Swift source code and generates a Figma canvas of screens, their destinations and API calls, and the flow between them — in minutes, not hours.

Supports **CleanSwift / VIP**, **MVC**, **MVVM**, and **SwiftUI** architectures.

---

## How to Use

### Step 1 — Clone the tools into your project

```bash
git clone https://github.com/Ntpstv/iOS-hld-for-existing-code.git Tools
```

Run this once from your project root. The `Tools/` folder is safe to add to `.gitignore`.

---

### Step 2 — Run the analyzer

```bash
bash Tools/hldgen.sh <ModuleDir>
```

`<ModuleDir>` is your module folder — `Calendar`, `Shop`, `MyApp`.
That is the only thing you supply. The script builds the analyzer, then works out the rest:

- **Screens** — every folder under `<Module>/<Module>/Scenes/` (or the whole module, if there
  is no `Scenes/`) that holds a `*ViewController.swift`. Modules without view controllers fall
  back to folders holding `*ViewModel.swift` / `*View.swift`.
- **Module name** — the last component of `<ModuleDir>`.
- **API endpoints** — the whole git repo is scanned, because a screen's Service, API class and
  Router usually live in different frameworks.
- **Flow file** — the first `*.swift` in `<Module>/<Module>/Flow/`, if that folder exists.

The bundle is written to `Tools/HLDFigmaPlugin/bundle.json`, beside the plugin's manifest; pass `-o <path>` to put it elsewhere. On completion the script also adds the bundle's
filename and the `Tools/` checkout to the host repo's `.gitignore`.

**Example:**
```bash
bash Tools/hldgen.sh Shop
```
```
Found 12 scene(s):
  Shop/Shop/Scenes/Checkout/Card
  Shop/Shop/Scenes/Checkout/Card/CardCheckoutDetails
  …
API scan root: /path/to/your-repo
No flow file found (skipping --flow-file)

Generating → Tools/HLDFigmaPlugin/bundle.json
wrote 12 scene(s) → Tools/HLDFigmaPlugin/bundle.json

✓ Done: Tools/HLDFigmaPlugin/bundle.json
  Paste into Figma plugin (Plugins → Development → iOS-hld-for-existing-code)
```

<details>
<summary>Running the analyzer directly, without the script</summary>

Every screen directory has to be listed explicitly — one directory produces one screen,
so passing a parent folder gives you a single card instead of the whole module:

```bash
swift run --package-path Tools/HLDGen hldgen \
  <sceneDir> [<sceneDir> ...] \
  --module <ModuleName> \
  --services-dir . \
  [--flow-file <Module>/<Module>/Flow/<File>.swift] \
  -o Tools/HLDFigmaPlugin/bundle.json
```

`--services-dir` is the root scanned for Service/API/Router classes (repeatable); without it,
no API endpoints are resolved.

Type `--module` by hand rather than pasting it from a slide or doc — editors turn
a double hyphen into an en dash, and `—module` fails with an unhelpful error.
</details>

---

### Step 3 — Load the plugin in Figma

The plugin is not on the Figma marketplace, so load it from disk. This needs the
**Figma desktop app** — the browser version has no Development menu.

1. Figma desktop → **menu → Plugins → Development → Import plugin from manifest…**
2. Choose `Tools/HLDFigmaPlugin/manifest.json`

One time only. After that it lives under **Plugins → Development → iOS-hld-for-existing-code**.

---

### Step 4 — Generate

1. Run **Plugins → Development → iOS-hld-for-existing-code**
2. Paste the contents of `Tools/HLDFigmaPlugin/bundle.json`
3. Click **Generate**

Your canvas now holds one column per screen:

- **Header** — the navigation title as the user sees it, and the view controller class.
- **Wireframe** — the storyboard/xib layout at its real positions.
- **GOES TO** — every destination the screen's actions reach. `→` is a screen in the same
  journey, `↗` is a screen in another journey or one that could not be matched. Rows naming a
  drawn screen are links: click to jump to it.
- **API** — each endpoint the screen calls (method + path), with request and response fields.
- **NOTIFICATION CENTER** / **LOCAL STORAGE** — shown only when the screen uses them.

Screens are grouped into labelled journeys (one per folder under `Scenes/`) and laid out left
to right in flow order. Arrows are drawn only between neighbouring columns and are labelled
with the action that leads there; a screen with several next screens branches through a
decision diamond. Longer hops are reached from the GOES TO rows instead.

Re-running clears the previous output first, so the board never stacks two generations
on top of each other. Anything you drew on the page yourself is left alone.

---

## Requirements

- Xcode with Swift toolchain
- Figma **desktop app** (free account is fine — the browser version cannot load local plugins)

## Repository Structure

```
Tools/
├── HLDGen/          # Swift package — the analyzer
│   └── Sources/HLDGen/
├── HLDFigmaPlugin/  # Figma plugin
│   ├── code.js
│   └── ui.html
└── hldgen.sh        # Optional convenience wrapper script
```

## License

MIT — see [LICENSE](LICENSE).
