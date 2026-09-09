import ChanAPI
import ChanCore
import ChanUI
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The composer: reply or new thread, with captcha or 4chan Pass verification.
public struct ComposerScreen: View {
    @StateObject private var store: ComposerStore
    @Environment(\.chanTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var showPhotoPicker = false
    @State private var captchaOffset: CGSize = .zero

    public init(board: BoardID, thread: PostNumber?) {
        _store = StateObject(
            wrappedValue: ComposerStore(board: board, thread: thread, environment: .shared)
        )
    }

    public var body: some View {
        NavigationView {
            Form {
                detailsSection
                attachmentSection
                verificationSection
                statusSection
            }
            .navigationTitle(store.isNewThread ? "New Thread" : "Reply")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isSubmitting {
                        ProgressView()
                    } else {
                        Button("Post") {
                            Task { await store.submit() }
                        }
                        .disabled(!store.canSubmit)
                        .tint(theme.accent)
                    }
                }
            }
            .task {
                if !store.usePass { await store.loadCaptcha() }
            }
            .onChange(of: store.didPost) { posted in
                guard posted else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
            }
            .onChange(of: store.usePass) { usePass in
                Task { if !usePass { await store.loadCaptcha() } }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker { data, filename, mime in
                store.attach(data: data, filename: filename, mimeType: mime)
            }
        }
    }

    // MARK: - Sections

    private var detailsSection: some View {
        Section("Post") {
            TextField("Name (Anonymous)", text: $store.name)
                .autocapitalization(.none)
            TextField("Email (sage)", text: $store.email)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            if store.isNewThread {
                TextField("Subject", text: $store.subject)
            }

            ZStack(alignment: .topLeading) {
                if store.comment.isEmpty {
                    Text("Comment")
                        .foregroundColor(theme.tertiaryText)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: $store.comment)
                    .frame(minHeight: 120)
                    .disableAutocorrection(true)
            }

            TextField("File tag (optional)", text: $store.fileTag)
            Toggle("Spoiler image", isOn: $store.isSpoiler)
                .disabled(store.attachment == nil)
        }
    }

    private var attachmentSection: some View {
        Section("Attachment") {
            if let attachment = store.attachment {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.subheadline.weight(.semibold))
                        Text(ChanFormat.bytes(attachment.data.count))
                            .font(.caption)
                            .foregroundColor(theme.secondaryText)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) { store.removeAttachment() }
                }
            } else {
                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Choose photo", systemImage: "photo")
                }
                .tint(theme.accent)
            }
        }
    }

    @ViewBuilder
    private var verificationSection: some View {
        Section("Verification") {
            Toggle("Use 4chan Pass", isOn: $store.usePass)

            if store.usePass {
                TextField("Pass ID", text: $store.passID)
                    .keyboardType(.numberPad)
                SecureField("PIN", text: $store.passPIN)
                    .keyboardType(.numberPad)
                Button("Authenticate") {
                    Task { await store.authenticatePass() }
                }
                .tint(theme.accent)
            } else {
                if let background = store.captchaBackground, let foreground = store.captchaForeground {
                    ZStack {
                        Image(uiImage: background)
                            .resizable()
                            .scaledToFit()
                        Image(uiImage: foreground)
                            .resizable()
                            .scaledToFit()
                            .offset(captchaOffset)
                            .gesture(
                                DragGesture().onChanged { captchaOffset = $0.translation }
                            )
                    }
                    .frame(height: 90)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: ChanRadius.small, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            Task { await store.loadCaptcha() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(6)
                        }
                    }

                    TextField("Type the characters", text: $store.captchaResponse)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))
                } else if store.cooldownRemaining > 0 {
                    Text("Cooldown: \(store.cooldownRemaining)s")
                        .foregroundColor(theme.secondaryText)
                } else {
                    Button("Load captcha") {
                        Task { await store.loadCaptcha() }
                    }
                    .tint(theme.accent)
                }

                Text("Drag the characters onto the background, then type them.")
                    .font(.caption2)
                    .foregroundColor(theme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let message = store.statusMessage {
            Section {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(store.didPost ? theme.accent : theme.danger)
            }
        }
    }
}

/// A single-image picker backed by `PHPickerViewController` (no permission prompt).
struct PhotoPicker: UIViewControllerRepresentable {
    let onPicked: (Data, String, String) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: (Data, String, String) -> Void

        init(onPicked: @escaping (Data, String, String) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }

            let typeIdentifier = provider.registeredTypeIdentifiers.first ?? UTType.image.identifier
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [onPicked] data, _ in
                guard let data else { return }
                let type = UTType(typeIdentifier)
                let mime = type?.preferredMIMEType ?? "application/octet-stream"
                let ext = type?.preferredFilenameExtension ?? "jpg"
                let base = provider.suggestedName ?? "upload"
                DispatchQueue.main.async {
                    onPicked(data, "\(base).\(ext)", mime)
                }
            }
        }
    }
}
