import ChanCore
import ChanUI
import SwiftUI

/// The filter rule builder: keyword/regex/poster/tripcode/capcode/filename rules
/// scoped globally or to one board.
public struct FiltersScreen: View {
    @State private var filters: [ChanFilter] = []
    @State private var editing: ChanFilter?
    @State private var isAdding = false

    @Environment(\.chanTheme) private var theme

    public init() {}

    public var body: some View {
        List {
            if filters.isEmpty {
                VStack(alignment: .leading, spacing: ChanSpacing.s) {
                    Text("No filters")
                        .font(.headline)
                        .foregroundColor(theme.primaryText)
                    Text("Rules hide or highlight posts and threads. Regex rules use ICU syntax and match case-insensitively.")
                        .font(.footnote)
                        .foregroundColor(theme.secondaryText)
                }
                .padding(.vertical, ChanSpacing.s)
                .listRowBackground(theme.surface)
            }

            ForEach(filters) { filter in
                Button {
                    editing = filter
                } label: {
                    row(filter)
                }
                .buttonStyle(.plain)
                .listRowBackground(theme.surface)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    try? AppEnvironment.shared.database.deleteFilter(id: filters[index].id)
                }
                load()
            }
        }
        .listStyle(.plain)
        .navigationTitle("Filters")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .tint(theme.accent)
            }
        }
        .onAppear { load() }
        .sheet(isPresented: $isAdding) {
            FilterEditor(filter: nil) { saved in
                try? AppEnvironment.shared.database.saveFilter(saved)
                load()
            }
            .environment(\.chanTheme, theme)
        }
        .sheet(item: $editing) { filter in
            FilterEditor(filter: filter) { saved in
                try? AppEnvironment.shared.database.saveFilter(saved)
                load()
            }
            .environment(\.chanTheme, theme)
        }
    }

    private func row(_ filter: ChanFilter) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ChanTag(text: filter.action.label.uppercased(), color: filter.action == .highlight ? theme.accent : theme.danger)
                ChanTag(text: filter.kind.label.uppercased(), color: theme.secondaryText)
                if let board = filter.board {
                    ChanTag(text: "/\(board.rawValue)/", color: theme.tertiaryText)
                } else {
                    ChanTag(text: "ALL", color: theme.tertiaryText)
                }
                Spacer()
                if !filter.enabled {
                    Text("off").font(.caption2).foregroundColor(theme.tertiaryText)
                }
            }

            Text(filter.pattern)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(theme.primaryText)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func load() {
        filters = (try? AppEnvironment.shared.database.filters()) ?? []
    }
}

/// Add or edit one rule.
struct FilterEditor: View {
    let filter: ChanFilter?
    let onSave: (ChanFilter) -> Void

    @State private var kind: ChanFilterKind
    @State private var action: ChanFilterAction
    @State private var pattern: String
    @State private var board: String
    @State private var enabled: Bool

    @Environment(\.chanTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    init(filter: ChanFilter?, onSave: @escaping (ChanFilter) -> Void) {
        self.filter = filter
        self.onSave = onSave
        _kind = State(initialValue: filter?.kind ?? .keyword)
        _action = State(initialValue: filter?.action ?? .hidePost)
        _pattern = State(initialValue: filter?.pattern ?? "")
        _board = State(initialValue: filter?.board?.rawValue ?? "")
        _enabled = State(initialValue: filter?.enabled ?? true)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Match") {
                    Picker("Kind", selection: $kind) {
                        ForEach(ChanFilterKind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    TextField("Pattern", text: $pattern)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))
                    TextField("Board (blank = everywhere)", text: $board)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section("Action") {
                    Picker("Action", selection: $action) {
                        ForEach(ChanFilterAction.allCases, id: \.self) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    Toggle("Enabled", isOn: $enabled)
                }

                if !pattern.isEmpty {
                    Section("Preview") {
                        Text("Matches case-insensitively against post text\(kind == .filename ? " and filenames" : "").")
                            .font(.caption)
                            .foregroundColor(theme.secondaryText)
                    }
                }
            }
            .navigationTitle(filter == nil ? "New Filter" : "Edit Filter")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        let trimmedBoard = board.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = ChanFilter(
            id: filter?.id ?? 0,
            board: trimmedBoard.isEmpty ? nil : BoardID(trimmedBoard),
            kind: kind,
            pattern: pattern,
            action: action,
            enabled: enabled,
            createdAt: filter?.createdAt ?? Date()
        )
        onSave(saved)
        ChanHaptics.success()
        dismiss()
    }
}
