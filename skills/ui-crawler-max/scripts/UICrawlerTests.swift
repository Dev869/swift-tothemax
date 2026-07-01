import XCTest

/// ui-crawler-max — autonomous UI crawler (data collection, not judgment).
///
/// Drop this file into your app's UI-testing bundle target (e.g. MyAppUITests).
/// Run via scripts/crawl.sh, which passes config through xcodebuild's
/// TEST_RUNNER_ env prefix. All artifacts land in $CRAWL_ARTIFACTS:
///   journal.jsonl                 one JSON object per step
///   screens/<signature>.png       first screenshot of each new screen
///   screens/<signature>.txt       accessibility hierarchy dump (app.debugDescription)
///   crash-<step>.json             crash record + last-10-step repro slice
@MainActor   // XCUIAutomation is MainActor-isolated under Swift 6 language mode
final class UICrawlerTests: XCTestCase {

    // MARK: - Config (env, prefix-stripped by xcodebuild from TEST_RUNNER_CRAWL_*)
    private var app: XCUIApplication!
    private var artifactsDir: URL!
    private var journalURL: URL!
    private var maxSteps = 150
    private var deadline = Date.distantFuture
    private var denyList: [String] = []

    // MARK: - Crawl state
    private var step = 0
    private var visitedElements = Set<String>()   // element keys ever acted on (incl. crashers)
    private var knownScreens = Set<String>()      // screen signatures already captured
    private var scrollAttempts: [String: Int] = [:]
    private var recentSteps: [String] = []        // ring buffer: last 10 journal lines (crash repro)
    private var crashCount = 0

    private static let defaultDenyList =
        "delete,remove,erase,reset,pay,purchase,buy,subscribe,checkout,sign out,log out,logout,send,report,block"
    private static let elementCap = 80            // per-query scan cap: keeps snapshots fast
    private static let maxScrollsPerScreen = 3

    // Called from testCrawl(), not setUpWithError(): setUp overrides stay nonisolated
    // under Swift 6 and cannot touch this MainActor-isolated state without warnings.
    private func configure() throws {
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        maxSteps = Int(env["CRAWL_MAX_STEPS"] ?? "") ?? 150
        deadline = Date().addingTimeInterval((Double(env["CRAWL_MAX_MINUTES"] ?? "") ?? 5) * 60)
        denyList = (env["CRAWL_DENYLIST"] ?? Self.defaultDenyList)
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        artifactsDir = URL(fileURLWithPath: env["CRAWL_ARTIFACTS"]
            ?? NSTemporaryDirectory() + "/crawl-artifacts", isDirectory: true)
        try FileManager.default.createDirectory(
            at: artifactsDir.appendingPathComponent("screens"), withIntermediateDirectories: true)
        journalURL = artifactsDir.appendingPathComponent("journal.jsonl")
        if !FileManager.default.fileExists(atPath: journalURL.path) {
            FileManager.default.createFile(atPath: journalURL.path, contents: nil)
        }

        // Permission alerts (photos, notifications, location, ...). Monitors fire lazily,
        // when a later interaction is blocked by the alert — our constant tapping triggers them.
        addUIInterruptionMonitor(withDescription: "system-permission-alert") { [weak self] alert in
            MainActor.assumeIsolated {   // handler runs on main; SDK signature is nonisolated
                for choice in ["Allow While Using App", "Allow Once", "Allow", "OK", "Continue"] {
                    let button = alert.buttons[choice]
                    if button.exists {
                        self?.journal(action: "dismissAlert", label: choice, type: "alert",
                                      signature: "system", result: "tapped \(choice)")
                        button.tap()
                        return true
                    }
                }
                return false
            }
        }
    }

    // MARK: - Main loop (greedy DFS with global visited-set)
    func testCrawl() throws {
        try configure()
        app = XCUIApplication()
        app.launchEnvironment["CRAWL_MODE"] = "1"   // app may opt into fixture data
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 30)

        while step < maxSteps, Date() < deadline {
            step += 1
            guard ensureRunning(afterAction: "loop-check") else { continue } // relaunched; re-enter
            let signature = screenSignature()
            recordScreenIfNew(signature)

            if let target = nextTarget(on: signature) {
                act(on: target, signature: signature)
            } else if scrollAttempts[signature, default: 0] < Self.maxScrollsPerScreen {
                scrollAttempts[signature, default: 0] += 1
                app.swipeUp()   // reveal off-screen elements
                journal(action: "scroll", label: "", type: "screen", signature: signature, result: "swipeUp")
            } else if goBack(from: signature) {
                journal(action: "back", label: "", type: "navigation", signature: signature, result: "ok")
            } else {
                journal(action: "relaunch", label: "", type: "app", signature: signature,
                        result: "exhausted screen, no back route")
                app.terminate()
                app.launch()
            }
        }
        journal(action: "done", label: "", type: "crawl", signature: "",
                result: "steps=\(step) screens=\(knownScreens.count) crashes=\(crashCount)")
    }

    // MARK: - Target selection (element-wise, precise taps — never coordinates)
    // .button covers tab-bar, nav-bar, back, and segmented-control child buttons.
    private func act(on target: (element: XCUIElement, type: String, key: String), signature: String) {
        // Mark visited BEFORE tapping: a crashing element must never be tapped twice.
        visitedElements.insert(target.key)
        let label = target.element.label
        target.element.tap()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6)) // let UI settle
        if ensureRunning(afterAction: "tap '\(label)' (\(target.type))") {
            journal(action: "tap", label: label, type: target.type, signature: signature, result: "ok")
        }
    }

    private func nextTarget(on signature: String) -> (element: XCUIElement, type: String, key: String)? {
        let kinds: [(XCUIElement.ElementType, String)] =
            [(.button, "button"), (.cell, "cell"), (.switch, "switch"), (.segmentedControl, "segmentedControl")]
        for (type, name) in kinds {
            for el in app.descendants(matching: type).allElementsBoundByIndex.prefix(Self.elementCap) {
                guard el.exists, el.isHittable else { continue }
                let label = el.label
                let key = elementKey(el, typeName: name, label: label, signature: signature)
                guard !visitedElements.contains(key) else { continue }
                if isDenied(label) {
                    visitedElements.insert(key)
                    journal(action: "skipDenied", label: label, type: name, signature: signature,
                            result: "matched deny-list")
                    continue
                }
                return (el, name, key)
            }
        }
        return nil
    }

    private func isDenied(_ label: String) -> Bool {
        let l = label.lowercased()
        return denyList.contains { l.contains($0) }
    }

    private func elementKey(_ el: XCUIElement, typeName: String, label: String, signature: String) -> String {
        let f = el.frame  // rounded to 10pt buckets: tolerant of sub-pixel layout jitter
        return "\(signature)|\(typeName)|\(el.identifier)|\(label)|" +
               "\(Int(f.minX / 10)),\(Int(f.minY / 10)),\(Int(f.width / 10)),\(Int(f.height / 10))"
    }

    // MARK: - Screen signature (hash of identifiers + labels + rounded frames)
    private func screenSignature() -> String {
        var parts: [String] = []
        for el in app.descendants(matching: .any).allElementsBoundByIndex.prefix(Self.elementCap) {
            guard el.exists else { continue }
            let f = el.frame
            parts.append("\(el.elementType.rawValue):\(el.identifier):\(el.label):" +
                         "\(Int(f.minX / 10)),\(Int(f.minY / 10)),\(Int(f.width / 10)),\(Int(f.height / 10))")
        }
        var hash: UInt64 = 0xcbf29ce484222325   // FNV-1a
        for byte in parts.sorted().joined(separator: "|").utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(format: "%016llx", hash)
    }

    private func recordScreenIfNew(_ signature: String) {
        guard knownScreens.insert(signature).inserted else { return }
        let screens = artifactsDir.appendingPathComponent("screens")
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: screens.appendingPathComponent("\(signature).png"))
        try? app.debugDescription
            .write(to: screens.appendingPathComponent("\(signature).txt"), atomically: true, encoding: .utf8)
        journal(action: "newScreen", label: "", type: "screen", signature: signature,
                result: "screenshot + hierarchy saved")
    }

    // MARK: - Crash detection (after EVERY tap)
    @discardableResult
    private func ensureRunning(afterAction action: String) -> Bool {
        switch app.state {
        case .runningForeground:
            return true
        case .runningBackground, .runningBackgroundSuspended:
            // Tap opened another app (Safari, Settings, share sheet target). Come back.
            journal(action: "leftApp", label: "", type: "app", signature: "", result: action)
            app.activate()
            return app.wait(for: .runningForeground, timeout: 10)
        default: // .notRunning / .unknown after a tap ⇒ crash
            crashCount += 1
            let record: [String: Any] = [
                "crashDetected": true, "step": step, "lastAction": action,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "repro": recentSteps]   // last 10 journal steps
            if let data = try? JSONSerialization.data(withJSONObject: record, options: .prettyPrinted) {
                try? data.write(to: artifactsDir.appendingPathComponent("crash-\(step).json"))
            }
            journal(action: "crashDetected", label: "", type: "app", signature: "", result: action)
            app.launch()   // element that crashed is already in visitedElements — never re-tapped
            _ = app.wait(for: .runningForeground, timeout: 30)
            return false
        }
    }

    // MARK: - Back navigation: nav back button → dismiss buttons → edge swipe → caller relaunches
    private func goBack(from signature: String) -> Bool {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists, back.isHittable {
            back.tap()
            if ensureRunning(afterAction: "navBack"), screenSignature() != signature { return true }
        }
        for label in ["Done", "Close", "Cancel", "Dismiss"] {
            let button = app.buttons[label]
            if button.exists, button.isHittable {
                button.tap()
                if ensureRunning(afterAction: "dismiss \(label)"), screenSignature() != signature { return true }
            }
        }
        // Last resort before relaunch: interactive-pop edge swipe (coordinates unavoidable here).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        return ensureRunning(afterAction: "edgeSwipe") && screenSignature() != signature
    }

    // MARK: - Journal (JSON Lines, append-only)
    private func journal(action: String, label: String, type: String, signature: String, result: String) {
        let entry: [String: Any] = [
            "step": step, "screenSignature": signature, "action": action,
            "elementLabel": label, "elementType": type,
            "timestamp": ISO8601DateFormatter().string(from: Date()), "result": result]
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        recentSteps.append(line)
        if recentSteps.count > 10 { recentSteps.removeFirst() }
        if let handle = try? FileHandle(forWritingTo: journalURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
        }
    }
}
