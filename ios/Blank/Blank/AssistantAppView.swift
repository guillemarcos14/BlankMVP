import AVFoundation
import Security
import Speech
import SwiftUI

enum AssistantAppSession {
    private static let service = "com.blanknfc.app.assistant.session"

    static func save(accessToken: String, refreshToken: String) {
        save(accessToken, account: "access")
        save(refreshToken, account: "refresh")
    }

    static func token(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ value: String, account: String) {
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

struct AssistantAppTurn: Decodable, Identifiable {
    let id: String
    let userText: String
    let assistantText: String
    let status: String
    let actionId: String
    let actionLabel: String
    let actionStatus: String
    let createdAt: String

    var canApply: Bool {
        !actionId.isEmpty && ["queued", "delivered"].contains(actionStatus)
    }
}

private struct AssistantAppEnvelope: Decodable {
    let ok: Bool
    let turns: [AssistantAppTurn]?
    let turn: AssistantAppTurn?
}

private enum AssistantAppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        if case let .message(value) = self { return value }
        return nil
    }
}

struct AssistantAppClient {
    func history() async throws -> [AssistantAppTurn] {
        let result = try await request(action: "history", extra: [:])
        return result.turns ?? []
    }

    func send(text: String, turnId: String) async throws -> AssistantAppTurn {
        let result = try await request(action: "send", extra: ["text": text, "turn_id": turnId])
        guard let turn = result.turn else { throw AssistantAppError.message("Blankmind did not return a reply.") }
        return turn
    }

    private func request(action: String, extra: [String: Any]) async throws -> AssistantAppEnvelope {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "BlankMembershipAPIBaseURL") as? String,
              !raw.isEmpty, !raw.contains("$("), let base = URL(string: raw) else {
            throw AssistantAppError.message("Blankmind is not configured in this build.")
        }
        guard let access = AssistantAppSession.token("access") else {
            throw AssistantAppError.message("Verify your phone to use Blankmind in the app.")
        }
        var body = extra
        body["action"] = action
        body["app_install_id"] = BlankSharedState.appInstallId
        let payload = try JSONSerialization.data(withJSONObject: body)
        let first = try await post(base: base, path: "assistant-app", payload: payload, token: access)
        if first.1.statusCode == 401 {
            guard let refreshed = try await refresh(base: base) else {
                throw AssistantAppError.message("Your session expired. Verify your phone again.")
            }
            return try decode(try await post(base: base, path: "assistant-app", payload: payload, token: refreshed))
        }
        return try decode(first)
    }

    private func refresh(base: URL) async throws -> String? {
        guard let refresh = AssistantAppSession.token("refresh") else { return nil }
        let payload = try JSONSerialization.data(withJSONObject: [
            "action": "refresh_session", "refresh_token": refresh,
        ])
        let response = try await post(base: base, path: "app-auth", payload: payload, token: nil)
        guard (200..<300).contains(response.1.statusCode),
              let data = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any],
              let access = data["access_token"] as? String, !access.isEmpty else { return nil }
        AssistantAppSession.save(accessToken: access, refreshToken: data["refresh_token"] as? String ?? refresh)
        return access
    }

    private func post(base: URL, path: String, payload: Data, token: String?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = payload
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AssistantAppError.message("No response from Blankmind.") }
        return (data, http)
    }

    private func decode(_ response: (Data, HTTPURLResponse)) throws -> AssistantAppEnvelope {
        guard (200..<300).contains(response.1.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: response.0) as? [String: Any])?["error"] as? String
            throw AssistantAppError.message((detail ?? "Blankmind is unavailable right now.").replacingOccurrences(of: "_", with: " "))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AssistantAppEnvelope.self, from: response.0)
    }
}

@MainActor
final class AssistantSpeechInput: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var error: String?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if isRecording { stop(); return }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized else { self.error = "Enable Speech Recognition in Settings."; return }
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    DispatchQueue.main.async {
                        if allowed { self.start() }
                        else { self.error = "Enable Microphone access in Settings." }
                    }
                }
            }
        }
    }

    private func start() {
        guard let recognizer, recognizer.isAvailable else {
            error = "Speech Recognition is unavailable right now."
            return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
            isRecording = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                DispatchQueue.main.async {
                    if let result { self?.transcript = result.bestTranscription.formattedString }
                    if failure != nil || result?.isFinal == true { self?.stop() }
                }
            }
        } catch {
            stop()
            self.error = "Could not start the microphone."
        }
    }

    func stop() {
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct AssistantAppView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var speech = AssistantSpeechInput()
    @State private var turns: [AssistantAppTurn] = []
    @State private var draft = ""
    @State private var pendingTurnId: String?
    @State private var isSending = false
    @State private var error: String?
    @State private var showHistory = false
    @State private var showPhoneSignIn = false
    @State private var showWhatsApp = false
    @Environment(\.scenePhase) private var scenePhase

    let onApplyAction: (String) -> Void

    private var latest: AssistantAppTurn? { turns.last(where: { $0.status == "completed" }) }
    private var foreground: Color { sessionStore.isBlankActive ? .white : BlankColors.charcoal }
    private var background: Color { sessionStore.isBlankActive ? BlankColors.charcoal : .white }

    var body: some View {
        VStack(spacing: 0) {
            Menu {
                Button("Conversation history", systemImage: "clock.arrow.circlepath") { showHistory = true }
                Button("Verify phone", systemImage: "iphone") { showPhoneSignIn = true }
                Button("WhatsApp connection", systemImage: "message") { showWhatsApp = true }
                Button("Close", systemImage: "xmark") { dismiss() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 23, weight: .bold))
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Blankmind menu")
            .padding(.top, 8)

            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        if let latest {
                            Text(latest.assistantText)
                                .font(.blankInter(size: 28, weight: .regular, relativeTo: .largeTitle))
                                .tracking(-0.5)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Blankmind: \(latest.assistantText)")
                            if latest.canApply {
                                Button {
                                    onApplyAction(latest.actionId)
                                    dismiss()
                                } label: {
                                    Text(latest.actionLabel.isEmpty ? "Apply now" : latest.actionLabel)
                                        .font(.blankInter(size: 17, weight: .semibold))
                                        .padding(.horizontal, 26)
                                        .frame(minHeight: 52)
                                        .background(Capsule().fill(foreground))
                                        .foregroundStyle(background)
                                }
                                .accessibilityHint("Opens the native action on your selected distractions")
                            } else if !latest.actionId.isEmpty {
                                Text(actionOutcome(latest.actionStatus))
                                    .font(.blankInter(size: 15))
                                    .foregroundStyle(foreground.opacity(0.65))
                            }
                        } else if isSending {
                            ProgressView().tint(foreground)
                        } else {
                            Text(Locale.current.languageCode == "es" ? "¿Qué tienes en mente?" : "What is on your mind?")
                                .font(.blankInter(size: 28, weight: .regular, relativeTo: .largeTitle))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: geometry.size.height * 0.72, alignment: .center)
                    .padding(.horizontal, 28)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            if let error {
                Text(error).font(.blankInter(size: 13)).foregroundStyle(BlankColors.red)
                    .padding(.horizontal, 28).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Write a message", text: $draft, axis: .vertical)
                    .font(.blankInter(size: 16))
                    .lineLimit(1...5)
                    .submitLabel(.send)
                    .onSubmit { Task { await send() } }
                    .padding(.vertical, 12)
                    .accessibilityLabel("Message Blankmind")
                Button { speech.toggle() } label: {
                    Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic")
                        .font(.system(size: 21))
                        .frame(width: 36, height: 44)
                }
                .accessibilityLabel(speech.isRecording ? "Stop dictation" : "Dictate message")
                if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { Task { await send() } } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 28))
                            .frame(width: 36, height: 44)
                    }
                    .disabled(isSending)
                    .accessibilityLabel("Send message")
                }
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .background(Capsule().fill(foreground.opacity(sessionStore.isBlankActive ? 0.11 : 0.06)))
            .padding(.horizontal, 22)
            .padding(.bottom, 12)
        }
        .foregroundStyle(foreground)
        .background(background.ignoresSafeArea())
        .preferredColorScheme(sessionStore.isBlankActive ? .dark : .light)
        .task { await reload() }
        .onChange(of: speech.transcript) { draft = $0 }
        .onChange(of: speech.error) { error = $0 }
        .onReceive(Timer.publish(every: 8, on: .main, in: .common).autoconnect()) { _ in
            if let latest, !latest.actionId.isEmpty,
               !["verified", "delayed", "failed", "dismissed", "expired", "superseded"].contains(latest.actionStatus) {
                Task { await reload() }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await reload() } }
        }
        .sheet(isPresented: $showHistory, onDismiss: { Task { await reload() } }) {
            AssistantAppHistoryView(turns: turns, foreground: foreground, background: background)
        }
        .sheet(isPresented: $showPhoneSignIn, onDismiss: { Task { await reload() } }) {
            AppPhoneSignInSheet(initialPhone: BlankSharedState.defaults.string(forKey: "blankAssistantPhoneNumber") ?? "")
        }
        .sheet(isPresented: $showWhatsApp) {
            AssistantConnectSheet(
                whatsAppNumber: Bundle.main.object(forInfoDictionaryKey: "BlankWhatsAppPhoneNumber") as? String,
                smsNumber: Bundle.main.object(forInfoDictionaryKey: "BlankSMSPhoneNumber") as? String,
                openURL: openURL, initialContext: [:]
            )
        }
    }

    private func reload() async {
        do { turns = try await AssistantAppClient().history(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        speech.stop()
        isSending = true
        error = nil
        do {
            let turnId = pendingTurnId ?? UUID().uuidString.lowercased()
            pendingTurnId = turnId
            let turn = try await AssistantAppClient().send(text: text, turnId: turnId)
            turns.append(turn)
            draft = ""
            pendingTurnId = nil
        } catch {
            self.error = error.localizedDescription
            if let turnId = pendingTurnId,
               let recoveredTurns = try? await AssistantAppClient().history(),
               let recovered = recoveredTurns.first(where: { $0.id == turnId }) {
                if recovered.status == "completed" {
                    turns.append(recovered)
                    draft = ""
                    pendingTurnId = nil
                    self.error = nil
                } else if recovered.status == "failed" {
                    pendingTurnId = nil
                }
            }
        }
        isSending = false
    }

    private func actionOutcome(_ status: String) -> String {
        switch status {
        case "verified": return "Applied and verified on iPhone"
        case "delayed": return "Applied after a delay"
        case "failed": return "Could not apply on iPhone"
        case "dismissed": return "Cancelled"
        case "expired", "superseded": return "This action is no longer available"
        default: return "Waiting for iPhone confirmation"
        }
    }
}

private struct AssistantAppHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let turns: [AssistantAppTurn]
    let foreground: Color
    let background: Color

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(turns) { turn in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("You").font(.blankInter(size: 12, weight: .semibold))
                                .foregroundStyle(foreground.opacity(0.55))
                            Text(turn.userText).font(.blankInter(size: 16))
                            Text("Blankmind").font(.blankInter(size: 12, weight: .semibold))
                                .foregroundStyle(foreground.opacity(0.55))
                            Text(turn.assistantText.isEmpty ? "No reply saved" : turn.assistantText)
                                .font(.blankInter(size: 16))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                }
                .padding(24)
            }
            .navigationTitle("Conversation history")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .foregroundStyle(foreground)
        .background(background.ignoresSafeArea())
    }
}
