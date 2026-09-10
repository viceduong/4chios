import ChanCore
import ChanUI
import SwiftUI

/// The rule builder for the filter language: pick the fields to search, the
/// match mode, the board scope, and what happens on a hit.
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
                    Text("Rules can collapse a post to a stub, hide it, hide the whole thread, or highlight it — matched against the fields you choose, per board or everywhere.")
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                ChanTag(
                    text: filter.action.label.uppercased(),
                    color: tagColor(for: filter.action)
                )
                ChanTag(text: filter.match.label.uppercased(), color: theme.secondaryText)
                if !filter.enabled {
                    ChanTag(text: "OFF", color: theme.tertiaryText)
                }
                Spacer()
                if ChanFilterEngine.validate(filter) != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(theme.danger)
                }
            }

            Text(filter.pattern)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(theme.primaryText)
                .lineLimit(2)

            Text("\(filter.fields.map(\.label).joined(separator: ", ")) · \(filter.scope.summary)")
                .font(.caption2)
                .foregroundColor(theme.tertiaryText)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func tagColor(for action: ChanFilterAction) -> Color {
        switch action {
        case .highlight: return theme.accent
        case .stub: return theme.secondaryText
        case .hidePost, .hideThread: return theme.danger
        }
    }

    private func load() {
        filters = (try? AppEnvironment.shared.database.filters()) ?? []
    }
}

/// Add or edit one rule.
struct FilterEditor: View {
    let filter: ChanFilter?
    let onSave: (ChanFilter) -> Void

    @State private var fields: [ChanFilterField]
    @State private var match: ChanFilterMatch
    @State private var pattern: String
    @State private var includeText: String
    @State private var excludeText: String
    @State private var action: ChanFilterAction
    @State private var enabled: Bool
    /// Once the user picks a mode by hand, stop second-guessing them.
    @State private var matchWasChosen: Bool

    @Environment(\.chanTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    init(filter: ChanFilter?, onSave: @escaping (ChanFilter) -> Void) {
        self.filter = filter
        self.onSave = onSave
        _fields = State(initialValue: filter?.fields ?? ChanFilterField.standard)
        _match = State(initialValue: filter?.match ?? .keyword)
        _pattern = State(initialValue: filter?.pattern ?? "")
        _includeText = State(initialValue: filter?.scope.included.joined(separator: ", ") ?? "")
        _excludeText = State(initialValue: filter?.scope.excluded.joined(separator: ", ") ?? "")
        _action = State(initialValue: filter?.action ?? .stub)
        _enabled = State(initialValue: filter?.enabled ?? true)
        _matchWasChosen = State(initialValue: filter != nil)
    }

    var body: some View {
        NavigationView {
            Form {
                patternSection
                fieldsSection
                scopeSection
                actionSection

                if let problem = validationMessage {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundColor(theme.danger)
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
                        .disabled(isSaveDisabled)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Sections

    private var patternSection: some View {
        Section("Pattern") {
            Picker("Match", selection: $match) {
                ForEach(ChanFilterMatch.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .onChange(of: match) { _ in matchWasChosen = true }

            TextField(patternPlaceholder, text: $pattern)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(.system(.body, design: .monospaced))

            Text(matchHelp)
                .font(.caption2)
                .foregroundColor(theme.secondaryText)
        }
    }

    private var fieldsSection: some View {
        Section("Match in") {
            ForEach(ChanFilterField.allCases) { field in
                Toggle(field.label, isOn: fieldBinding(field))
            }
        }
    }

    private var scopeSection: some View {
        Section("Boards") {
            TextField("Only these (g, v, sfw, nsfw)", text: $includeText)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            TextField("Except these (e.g. pol, nsfw)", text: $excludeText)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            Text("Leave both empty to apply everywhere. `sfw` and `nsfw` mean every work-safe or non-work-safe board.")
                .font(.caption2)
                .foregroundColor(theme.secondaryText)
        }
    }

    private var actionSection: some View {
        Section("Action") {
            Picker("Action", selection: $action) {
                ForEach(ChanFilterAction.allCases) { candidate in
                    Text(candidate.label).tag(candidate)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Toggle("Enabled", isOn: $enabled)
        }
    }

    // MARK: - Helpers

    private func fieldBinding(_ field: ChanFilterField) -> Binding<Bool> {
        Binding(
            get: { fields.contains(field) },
            set: { isOn in
                if isOn {
                    guard !fields.contains(field) else { return }
                    fields.append(field)
                } else {
                    fields.removeAll { $0 == field }
                }
                if !matchWasChosen {
                    match = ChanFilterMatch.suggested(for: fields)
                }
            }
        )
    }

    private var patternPlaceholder: String {
        match == .regex ? "/pattern/flags" : "text to match"
    }

    private var matchHelp: String {
        switch match {
        case .keyword:
            return "Case-insensitive substring."
        case .regex:
            return "ICU regex. `/foo/` is case-sensitive and `/foo/i` is not; a bare pattern is case-insensitive. Flags: i, m, s, x."
        case .exact:
            return "Whole-field equality, case-insensitive. Best for IDs and MD5s."
        }
    }

    private var validationMessage: String? {
        ChanFilterEngine.validate(makeFilter(id: filter?.id ?? 0))
    }

    private var isSaveDisabled: Bool {
        validationMessage != nil
    }

    private func makeFilter(id: Int64) -> ChanFilter {
        ChanFilter(
            id: id,
            fields: fields,
            match: match,
            pattern: pattern,
            scope: ChanBoardScope(
                included: Self.parseList(includeText),
                excluded: Self.parseList(excludeText)
            ),
            action: action,
            enabled: enabled,
            createdAt: filter?.createdAt ?? Date()
        )
    }

    private static func parseList(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ", \n"))
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func save() {
        let saved = makeFilter(id: filter?.id ?? 0)
        onSave(saved)
        ChanHaptics.success()
        dismiss()
    }
}
