import SwiftUI

struct PluginBrowseView: View {
    @State private var searchQuery = ""
    @State private var selectedCategory = ""
    @State private var plugins: [RegistryPlugin] = []
    @State private var featuredPlugins: [RegistryPlugin] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var installingIDs: Set<String> = []

    private let categories = ["All", "ai", "translation", "productivity", "developer", "writing"]

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search plugins...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit { search() }
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = ""; loadAll() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.top, 12)

            // Category filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { category in
                        Button(action: {
                            selectedCategory = category == "All" ? "" : category
                            search()
                        }) {
                            Text(category.capitalized)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    (category == "All" && selectedCategory.isEmpty) || category == selectedCategory
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.secondary.opacity(0.1)
                                )
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            // Content
            if isLoading {
                Spacer()
                ProgressView("Loading plugins...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { loadAll() }
                }
                .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Featured section
                        if !featuredPlugins.isEmpty && searchQuery.isEmpty && selectedCategory.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Featured")
                                    .font(.headline)
                                    .padding(.horizontal)
                                    .padding(.top, 12)

                                ForEach(featuredPlugins) { plugin in
                                    RegistryPluginRow(
                                        plugin: plugin,
                                        isInstalling: installingIDs.contains(plugin.id),
                                        isInstalled: isInstalled(plugin.id),
                                        onInstall: { installPlugin(plugin) }
                                    )
                                }
                            }

                            Divider()
                                .padding(.vertical, 8)
                        }

                        // All / search results
                        if !plugins.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                if !searchQuery.isEmpty || !selectedCategory.isEmpty {
                                    Text("Results")
                                        .font(.headline)
                                        .padding(.horizontal)
                                        .padding(.top, 12)
                                }

                                ForEach(plugins) { plugin in
                                    RegistryPluginRow(
                                        plugin: plugin,
                                        isInstalling: installingIDs.contains(plugin.id),
                                        isInstalled: isInstalled(plugin.id),
                                        onInstall: { installPlugin(plugin) }
                                    )
                                }
                            }
                        } else if !searchQuery.isEmpty {
                            VStack(spacing: 8) {
                                Text("No plugins found")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Try a different search term")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 40)
                        }
                    }
                }
            }
        }
        .onAppear { loadAll() }
    }

    // MARK: - Actions

    private func loadAll() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let featured = try await PluginRegistryClient.shared.featured()
                let all = try await PluginRegistryClient.shared.search()
                await MainActor.run {
                    featuredPlugins = featured
                    plugins = all
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func search() {
        isLoading = true
        Task {
            do {
                let results = try await PluginRegistryClient.shared.search(
                    query: searchQuery.isEmpty ? nil : searchQuery,
                    category: selectedCategory.isEmpty ? nil : selectedCategory
                )
                await MainActor.run {
                    plugins = results
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func installPlugin(_ plugin: RegistryPlugin) {
        installingIDs.insert(plugin.id)
        Task {
            do {
                _ = try await PluginRegistryClient.shared.install(plugin: plugin)
                _ = await MainActor.run {
                    installingIDs.remove(plugin.id)
                }
            } catch {
                await MainActor.run {
                    installingIDs.remove(plugin.id)
                    print("Install failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func isInstalled(_ pluginID: String) -> Bool {
        PluginManager.shared.plugins.contains { $0.manifest.id == pluginID }
    }
}

// MARK: - Registry Plugin Row

private struct RegistryPluginRow: View {
    let plugin: RegistryPlugin
    let isInstalling: Bool
    let isInstalled: Bool
    let onInstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(plugin.name)
                        .font(.headline)
                    Text("v\(plugin.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(plugin.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Text("by \(plugin.author)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isInstalled {
                Text("Installed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            } else if isInstalling {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Install") { onInstall() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
