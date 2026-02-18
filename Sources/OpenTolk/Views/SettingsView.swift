import SwiftUI
import ServiceManagement
import AVFoundation

struct SettingsView: View {
    @State private var selectedTab = 0

    private let tabs = ["General", "Permissions", "Transcription", "Audio", "Hotkey", "Snippets", "Plugins", "Account"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(0..<tabs.count, id: \.self) { i in
                    Text(tabs[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            Group {
                switch selectedTab {
                case 0: GeneralTab()
                case 1: PermissionsTab()
                case 2: TranscriptionTab()
                case 3: AudioTab()
                case 4: HotkeyTab()
                case 5: SnippetsTab()
                case 6: PluginsTab()
                case 7: AccountTab()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 640, height: 440)
    }
}

// MARK: - Permissions Tab

private struct PermissionsTab: View {
    var body: some View {
        Form {
            Section("Required Permissions") {
                PermissionRowView(type: .microphone)
                PermissionRowView(type: .accessibility)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Transcription Tab

private struct TranscriptionTab: View {
    @State private var selectedProvider: TranscriptionProviderType = .cloud
    @State private var groqAPIKey: String = ""
    @State private var openaiAPIKey: String = ""
    @State private var showGroqKey = false
    @State private var showOpenAIKey = false

    var body: some View {
        Form {
            Section("Transcription Provider") {
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(TranscriptionProviderType.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: selectedProvider) { _, newValue in
                    Config.shared.selectedProvider = newValue
                }
            }

            switch selectedProvider {
            case .cloud:
                Section("OpenTolk Cloud") {
                    Text("No configuration needed. Works out of the box.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Text("Free: 5,000 words/month, 30s recordings, English only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Pro ($4.99/mo): Unlimited words, 120s recordings, all languages")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            case .groq:
                Section("Groq API Key") {
                    Text("Free forever with your own key. No limits.")
                        .foregroundStyle(.green)
                        .font(.callout)
                    HStack {
                        if showGroqKey {
                            TextField("gsk_...", text: $groqAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("gsk_...", text: $groqAPIKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            showGroqKey.toggle()
                        } label: {
                            Image(systemName: showGroqKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                    HStack {
                        Button("Save Key") {
                            KeychainHelper.save(key: "groq_api_key", value: groqAPIKey)
                            Config.shared.selectedProvider = .groq
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button("Get API Key") {
                            if let url = URL(string: "https://console.groq.com/keys") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .font(.callout)
                    }
                }
            case .openai:
                Section("OpenAI API Key") {
                    Text("Free forever with your own key. No limits.")
                        .foregroundStyle(.green)
                        .font(.callout)
                    HStack {
                        if showOpenAIKey {
                            TextField("sk-...", text: $openaiAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-...", text: $openaiAPIKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            showOpenAIKey.toggle()
                        } label: {
                            Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                    HStack {
                        Button("Save Key") {
                            KeychainHelper.save(key: "openai_api_key", value: openaiAPIKey)
                            Config.shared.selectedProvider = .openai
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button("Get API Key") {
                            if let url = URL(string: "https://platform.openai.com/api-keys") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .font(.callout)
                    }
                }
            case .local:
                Section("Local (On-Device)") {
                    Text("Coming soon. On-device Whisper transcription.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Text("Free forever. No limits. No internet required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            selectedProvider = Config.shared.selectedProvider
            groqAPIKey = KeychainHelper.load(key: "groq_api_key") ?? ""
            openaiAPIKey = KeychainHelper.load(key: "openai_api_key") ?? ""
        }
    }
}

// MARK: - Audio Tab

private struct AudioTab: View {
    @State private var selectedMicrophoneID: String = ""
    @State private var availableMicrophones: [(id: String, name: String)] = []
    @State private var silenceThreshold: Double = 0.01
    @State private var silenceDuration: Double = 1.5
    @State private var maxRecordingDuration: Double = 120.0
    @State private var language: String = "en"

    private var hasUnlimitedFeatures: Bool {
        Config.shared.selectedProvider.hasUnlimitedFeatures || SubscriptionManager.shared.isPro
    }

    private var effectiveMaxDuration: Double {
        hasUnlimitedFeatures ? 120.0 : 30.0
    }

    var body: some View {
        Form {
            Section("Microphone") {
                Picker("Input Device", selection: $selectedMicrophoneID) {
                    Text("System Default").tag("")
                    ForEach(availableMicrophones, id: \.id) { mic in
                        Text(mic.name).tag(mic.id)
                    }
                }
            }

            Section("Silence Detection") {
                HStack {
                    Text("Threshold (RMS)")
                    Spacer()
                    Slider(value: $silenceThreshold, in: 0.001...0.1, step: 0.001)
                        .frame(width: 180)
                    Text(String(format: "%.3f", silenceThreshold))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 50)
                }

                HStack {
                    Text("Duration (seconds)")
                    Spacer()
                    Slider(value: $silenceDuration, in: 0.5...5.0, step: 0.1)
                        .frame(width: 180)
                    Text(String(format: "%.1f", silenceDuration))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 50)
                }
            }

            Section("Recording") {
                HStack {
                    Text("Max duration (seconds)")
                    Spacer()
                    Slider(value: $maxRecordingDuration, in: 5...effectiveMaxDuration, step: 5)
                        .frame(width: 180)
                    Text(String(format: "%.0f", maxRecordingDuration))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 50)
                }
                if !hasUnlimitedFeatures {
                    Text("Cloud free tier limited to 30s. Upgrade to Pro or use your own API key for up to 120s.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Language") {
                if hasUnlimitedFeatures {
                    TextField("Language code (e.g., en, es, fr, de)", text: $language)
                        .textFieldStyle(.roundedBorder)
                } else {
                    HStack {
                        Text("English only")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Upgrade or use own key for all languages")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            let config = Config.shared
            selectedMicrophoneID = config.selectedMicrophoneID
            availableMicrophones = AudioRecorder.availableInputDevices().map { (id: $0.uid, name: $0.name) }
            silenceThreshold = Double(config.silenceThresholdRMS)
            silenceDuration = config.silenceDuration
            maxRecordingDuration = config.maxRecordingDuration
            language = config.language
        }
        .onDisappear {
            Config.shared.selectedMicrophoneID = selectedMicrophoneID
            Config.shared.silenceThresholdRMS = Float(silenceThreshold)
            Config.shared.silenceDuration = silenceDuration
            Config.shared.maxRecordingDuration = maxRecordingDuration
            Config.shared.language = language
        }
    }
}

// MARK: - Hotkey Tab

private struct HotkeyTab: View {
    @State private var holdThreshold: Double = 300
    @State private var selectedHotkey: HotkeyOption = .rightOption

    var body: some View {
        Form {
            Section("Dictation Hotkey") {
                Picker("Hotkey", selection: $selectedHotkey) {
                    ForEach(HotkeyOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .onChange(of: selectedHotkey) { _, newValue in
                    Config.shared.hotkeyCode = newValue
                }
                Text("Quick tap: auto-stop on silence. Hold: manual stop on release.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hold Detection") {
                HStack {
                    Text("Hold threshold (ms)")
                    Spacer()
                    Slider(value: $holdThreshold, in: 100...800, step: 50)
                        .frame(width: 180)
                    Text(String(format: "%.0f", holdThreshold))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 50)
                }
                Text("Time before a key press is considered a 'hold' vs a 'tap'")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            holdThreshold = Double(Config.shared.holdThresholdMs)
            selectedHotkey = Config.shared.hotkeyCode
        }
        .onDisappear {
            Config.shared.holdThresholdMs = Int(holdThreshold)
        }
    }
}

// MARK: - Account Tab

private struct AccountTab: View {
    @ObservedObject private var authManager = AuthManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var isSigningOut = false
    @State private var isSyncing = false

    var body: some View {
        Form {
            // Account section
            if authManager.isSignedIn {
                Section("Account") {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            if let name = authManager.user?.displayName {
                                Text(name)
                                    .fontWeight(.medium)
                            }
                            if let email = authManager.user?.email {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if subscriptionManager.isPro {
                        HStack {
                            Text("Sync")
                            Spacer()
                            if let lastSync = SyncManager.shared.lastSyncTime {
                                Text("Last: \(lastSync, style: .relative) ago")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Not yet synced")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button(isSyncing ? "Syncing..." : "Sync Now") {
                                isSyncing = true
                                SyncManager.shared.syncIfNeeded()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    isSyncing = false
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isSyncing)
                        }
                    } else {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.secondary)
                            Text("Upgrade to Pro for cloud sync")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(isSigningOut ? "Signing out..." : "Sign Out") {
                        isSigningOut = true
                        Task {
                            await authManager.signOut()
                            await MainActor.run { isSigningOut = false }
                        }
                    }
                    .foregroundStyle(.red)
                    .disabled(isSigningOut)
                }
            } else {
                Section("Account") {
                    SignInView()
                }
            }

            // Subscription section
            Section("Subscription") {
                HStack {
                    Text("Status")
                    Spacer()
                    if subscriptionManager.isPro {
                        HStack(spacing: 4) {
                            Text("Pro")
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                            if let plan = subscriptionManager.plan {
                                Text("(\(plan))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Free")
                            .foregroundStyle(.secondary)
                    }
                }

                if let periodEnd = subscriptionManager.currentPeriodEnd {
                    HStack {
                        Text("Renews")
                        Spacer()
                        Text(periodEnd, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if subscriptionManager.isPro {
                    Button("Manage Subscription") {
                        guard let token = AuthTokenStore.accessToken,
                              let url = URL(string: "\(Config.apiBaseURL)/manage?token=\(token)")
                        else { return }
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.bordered)
                } else if authManager.isSignedIn {
                    Button("Upgrade to Pro") {
                        SubscriptionManager.shared.openCheckout()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Usage This Month") {
                HStack {
                    Text("Words used")
                    Spacer()
                    Text("\(UsageTracker.shared.wordsUsed())")
                        .font(.system(.body, design: .monospaced))
                }
                HStack {
                    Text("Words remaining")
                    Spacer()
                    let remaining = UsageTracker.shared.wordsRemaining()
                    Text(remaining == Int.max ? "Unlimited" : "\(remaining)")
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
