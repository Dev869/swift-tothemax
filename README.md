# swift-tothemax

A Claude Code plugin covering every facet of Swift and Apple-platform development, current to mid-2026 (Swift 6.3 stable / 6.4 beta, Xcode 26.6, iOS 27 beta). All version-sensitive claims research-verified against swift.org, Swift Evolution, and developer.apple.com.

## Skills

| Skill | Facet |
|---|---|
| `apple-dev-conductor` | Orchestrator — routes multi-facet tasks through the suite in lifecycle order |
| `swift-language` | Swift 6.x language: concurrency, generics, ownership/performance, macros, API design, SwiftPM, interop, testing (8 reference files) |
| `swiftui-max` | SwiftUI: state/data flow, layout/animation, performance, platform integration |
| `apple-hig-ux` | Design judgment: HIG, platform idioms, accessibility, icons, "feels native" |
| `app-review-max` | App Review: rejection playbook, monetization compliance, submission checklist |
| `apple-legal-max` | Legal & privacy: privacy manifests, nutrition labels, ATT, GDPR/COPPA/DMA, document templates |
| `apple-release-ops` | Shipping: signing, TestFlight, App Store Connect, CI recipes, store presence |
| `ui-crawler-max` | Autonomous UI crawling: element-precise XCUITest exploration of every reachable screen, live console-error + crash capture with repro steps, Haiku-powered fast data labeling. Data collection only — fixes route to the other skills |

## How they flow together

`apple-dev-conductor` decomposes tasks along the lifecycle: **shape** (hig-ux) → **build** (swift-language + swiftui-max) → **compliance gates early** (legal-max, review-max) → **quality** (accessibility audit, tests) → **ship** (release-ops, then review-max as final gate) → **rejected/incident** (review-max playbook, release-ops triage). Decisions carry forward (data types collected → nutrition labels; monetization model → guideline 3.1.x). Conflict rule: this plugin wins on dated facts (versions, policy, legal); specialized companions win on workflow depth.

## Optional ecosystem companions

The suite detects and delegates to these when installed (`npx skills add <pkg>`):

| Companion | Install | Deepens |
|---|---|---|
| SwiftUI review (25K/22K installs) | `avdlee/swiftui-agent-skill@swiftui-expert-skill` · `twostraws/swiftui-agent-skill@swiftui-pro` | swiftui-max |
| Concurrency review (13K/7K) | `avdlee/swift-concurrency-agent-skill@swift-concurrency` · `twostraws/swift-concurrency-agent-skill@swift-concurrency-pro` | swift-language |
| Testing review (6K/3.6K) | `twostraws/swift-testing-agent-skill@swift-testing-pro` · `avdlee/swift-testing-agent-skill@swift-testing-expert` | swift-language |
| SwiftData (2.4K) | `dpearson2699/swift-ios-skills@swiftdata` | swift-language |
| SwiftUI perf audit (7.6K) | `dimillian/skills@swiftui-performance-audit` | swiftui-max |
| Xcode build suite (2.6–2.8K) | `avdlee/xcode-build-optimization-agent-skill@xcode-build-fixer` (+siblings) | apple-release-ops |
| Adversarial review sim (9.9K) | `github/awesome-copilot@apple-appstore-reviewer` | app-review-max |
| ASO / listing growth (1.2–1.4K) | `dpearson2699/swift-ios-skills@app-store-optimization` | app-review-max |
| ASC CLI ops (2–2.4K) | `rudrankriyam/app-store-connect-cli-skills@asc-metadata-sync` (+siblings) | apple-release-ops |
| HIG lookups (1.4K) | `nexu-io/open-design@apple-hig` | apple-hig-ux |

No quality ecosystem companion exists for the legal/privacy facet (verified July 2026); `apple-legal-max` is self-contained.

## Development

- `swift-tothemax-workspace/research/` — deep-research report + annotated findings behind the version claims.
- `skills/swift-language/evals/evals.json` — test cases for the eval loop (skill-creator process).
