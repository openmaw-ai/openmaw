import SwiftUI

struct SnippetsView: View {
    @State private var snippets: [Snippet] = []
    @State private var showingEditor = false
    @State private var editingSnippet: Snippet?

    var body: some View {
        VStack(spacing: 0) {
            if snippets.isEmpty {
                emptyState
            } else {
                snippetsList
            }
            Divider()
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { reload() }
        .sheet(isPresented: $showingEditor, onDismiss: reload) {
            SnippetEditorSheet(snippet: editingSnippet) { saved in
                let triggers = Snippet.parseTriggers(saved.triggers)
                if let existing = editingSnippet {
                    var updated = existing
                    updated.triggers = triggers
                    updated.body = saved.body
                    SnippetManager.shared.update(updated)
                } else {
                    SnippetManager.shared.add(triggers: triggers, body: saved.body)
                }
                editingSnippet = nil
                showingEditor = false
            } onCancel: {
                editingSnippet = nil
                showingEditor = false
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No Snippets")
                .font(.headline)
            Text("Add a snippet to expand trigger words into text")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Snippets List

    private var snippetsList: some View {
        List {
            ForEach(snippets) { snippet in
                SnippetRow(
                    snippet: snippet,
                    onToggle: { enabled in
                        SnippetManager.shared.setEnabled(enabled, for: snippet.id)
                        reload()
                    },
                    onEdit: {
                        editingSnippet = snippet
                        showingEditor = true
                    },
                    onDelete: {
                        SnippetManager.shared.delete(id: snippet.id)
                        reload()
                    }
                )
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Text("\(snippets.count) snippet\(snippets.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: {
                editingSnippet = nil
                showingEditor = true
            }) {
                Label("Add Snippet", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
    }

    private func reload() {
        SnippetManager.shared.reload()
        snippets = SnippetManager.shared.snippets
    }
}

// MARK: - Snippet Row

private struct SnippetRow: View {
    let snippet: Snippet
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isEnabled: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Trigger badges
            HStack(spacing: 4) {
                ForEach(snippet.triggers, id: \.self) { trigger in
                    Text(trigger)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isEnabled ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                        .foregroundColor(isEnabled ? .accentColor : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }

            // Body preview
            Text(snippet.body.replacingOccurrences(of: "\n", with: " "))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Spacer()

            // Edit
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit")

            // Delete
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red.opacity(0.7))
            .help("Delete")

            // Toggle
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: isEnabled) { _, newValue in
                    onToggle(newValue)
                }
        }
        .padding(.vertical, 4)
        .onAppear { isEnabled = snippet.isEnabled }
    }
}

// MARK: - Snippet Editor Sheet

struct SnippetEditorSheet: View {
    let snippet: Snippet?
    let onSave: ((triggers: String, body: String)) -> Void
    let onCancel: () -> Void

    @State private var triggersText = ""
    @State private var snippetBody = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(snippet == nil ? "New Snippet" : "Edit Snippet")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Form
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trigger Words")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("e.g., yes, yeah, yep", text: $triggersText)
                        .textFieldStyle(.roundedBorder)
                    Text("Comma-separated. Any of these words will activate the snippet.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Snippet Text")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextEditor(text: $snippetBody)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 100)
                        .border(Color.secondary.opacity(0.3))
                    Text("This text will be pasted when a trigger word is spoken")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave((triggers: triggersText, body: snippetBody))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(triggersText.trimmingCharacters(in: .whitespaces).isEmpty || snippetBody.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 360)
        .onAppear {
            if let snippet = snippet {
                triggersText = snippet.triggersDisplay
                snippetBody = snippet.body
            }
        }
    }
}

// MARK: - Snippets Tab (for SettingsView)

struct SnippetsTab: View {
    var body: some View {
        SnippetsView()
    }
}
