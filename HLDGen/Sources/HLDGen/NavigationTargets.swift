import Foundation

/// Screen classes a function body navigates to via `present(…)`, `push…(…)` or `show(…)`.
///
/// The argument is usually a local, not a type — `let vc = ThanksViewController.configuredWith(…)`
/// then `present(vc)` — so recording the argument text left destinations like `present:vc` and
/// `push:nav` that no renderer can place. Each argument is traced back to the class its variable
/// was built from, through a wrapping navigation controller if there is one. Alerts and action
/// sheets are not screens and are dropped, as is anything that cannot be traced to a class.
func navigationTargets(in body: String) -> [String] {
    let screenClass = #"\b([A-Z]\w*(?:ViewController|VC))\b"#
    var targets: [String] = []

    func resolve(_ token: String, depth: Int = 0) -> String? {
        guard depth < 4 else { return nil }
        if token.range(of: "^" + screenClass + "$", options: .regularExpression) != nil { return token }
        // `let vc = Foo.configuredWith(…)` / `let nav = UINavigationController(rootViewController: vc)`
        guard let assign = body.firstMatch(#"(?:let|var)\s+"# + token + #"\s*(?::\s*[\w.<>?]+)?\s*=\s*([^\n]+)"#)
        else { return nil }
        let rhs = assign[1]
        if let root = rhs.firstMatch(#"rootViewController:\s*(\w+)"#) {
            return resolve(root[1], depth: depth + 1)
        }
        if let cls = rhs.firstMatch(screenClass), !cls[1].hasPrefix("UI") { return cls[1] }
        return nil
    }

    for m in body.matches(#"\b(?:present|push\w*|show)\(\s*(\w+)"#) {
        let arg = m[1]
        if arg.range(of: #"(?i)alert|actionSheet|sheet"#, options: .regularExpression) != nil { continue }
        if let cls = resolve(arg), !targets.contains(cls) { targets.append(cls) }
    }
    return targets
}
