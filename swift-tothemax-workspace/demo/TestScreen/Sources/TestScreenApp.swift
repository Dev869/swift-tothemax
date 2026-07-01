import SwiftUI
import OSLog

@main
struct TestScreenApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") { HomeView() }
            Tab("Settings", systemImage: "gear") { SettingsView() }
        }
    }
}

// MARK: - Home

struct Item: Identifiable, Hashable {
    let id: Int
    var name: String { "Item \(id)" }
}

struct HomeView: View {
    private let items = (1...6).map(Item.init)
    @State private var showAlert = false
    private let log = Logger(subsystem: "dev.devinwilson.TestScreen", category: "home")

    var body: some View {
        NavigationStack {
            List {
                Section("Items") {
                    ForEach(items) { item in
                        NavigationLink(item.name, value: item)
                    }
                }
                Section("Actions") {
                    Button("Show Alert") { showAlert = true }
                    Button("Log Error") {
                        log.fault("Seeded fault: simulated subsystem failure at \(Date.now)")
                    }
                    // Seeded issue: image-only button with no accessibility label.
                    Button { log.info("mystery tapped") } label: {
                        Image(systemName: "sparkles")
                    }
                }
            }
            .navigationTitle("Home")
            .navigationDestination(for: Item.self) { DetailView(item: $0) }
            .alert("Hello from TestScreen", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

struct DetailView: View {
    let item: Item
    @State private var count = 0
    var body: some View {
        VStack(spacing: 20) {
            Text(item.name).font(.largeTitle)
            Text("Count: \(count)")
            Button("Increment") { count += 1 }
                .buttonStyle(.borderedProminent)
        }
        .navigationTitle(item.name)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @State private var notificationsOn = true
    @State private var volume = 0.5
    @State private var username = ""
    @State private var quality = "Medium"

    var body: some View {
        NavigationStack {
            Form {
                Section("Preferences") {
                    Toggle("Notifications", isOn: $notificationsOn)
                    Slider(value: $volume) { Text("Volume") }
                    TextField("Username", text: $username)
                    Picker("Quality", selection: $quality) {
                        ForEach(["Low", "Medium", "High"], id: \.self) { Text($0) }
                    }
                }
                Section("Danger Zone") {
                    Button("Crash") {
                        fatalError("Seeded crash: user tapped the Crash button")
                    }
                    .foregroundStyle(.red)
                    Button("Delete Account", role: .destructive) {
                        // Deny-listed by the crawler; must never be tapped.
                        preconditionFailure("Crawler safety failure: deny-listed button was tapped")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
