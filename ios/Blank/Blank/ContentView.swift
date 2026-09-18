import Foundation
import SwiftUI

struct ContentView: View {
    @State private var showingOnboardingDemo = false

    var body: some View {
        ZStack {
            if showingOnboardingDemo {
                SetupView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showingOnboardingDemo = false
                    }
                }
                .transition(.opacity)
            } else {
                HomeView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showingOnboardingDemo = true
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showingOnboardingDemo)
        .environment(\.blankMinimalAppearance, true)
    }
}

struct AssistantContextSyncClient {
    func sync(connectCode: String, channel: String, phoneNumber: String, payload: [String: Any]) async {
        guard let baseURL = configuredBaseURL(),
              !connectCode.isEmpty else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("assistant-channel"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        let body: [String: Any] = [
            "action": "sync_context",
            "connect_code": connectCode,
            "preferred_channel": channel,
            "user_phone": phoneNumber,
            "context": payload,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = data
        _ = try? await URLSession.shared.data(for: request)
    }

    private func configuredBaseURL() -> URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "BlankMembershipAPIBaseURL") as? String else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }
        return URL(string: trimmed)
    }
}

enum BlankedAgentMemory {
    private static let defaults = BlankSharedState.defaults
    private static let lastPromptKey = "blankedAgentLastPrompt"
    private static let lastIntentKey = "blankedAgentLastIntent"
    private static let lastPlanTitleKey = "blankedAgentLastPlanTitle"
    private static let lastPlanAppliedAtKey = "blankedAgentLastPlanAppliedAt"
    private static let lastPlanProtectedMinutesKey = "blankedAgentLastPlanProtectedMinutes"
    private static let lastPlanBreakCountKey = "blankedAgentLastPlanBreakCount"
    private static let mainAppsKey = "blankedAgentMainApps"
    private static let bedtimeMinuteKey = "blankedAgentBedtimeMinute"
    private static let patternClusterKey = "blankedAgentPatternCluster"
    private static let conversationKey = "blankedAgentShortConversation"
    private static let semanticStateKey = "blankedAgentSemanticState"
    private static let semanticStateTimestampKey = "blankedAgentSemanticStateTimestamp"
    private static let shortConversationTTL: TimeInterval = 2 * 60 * 60

    static func recentSemanticState(now: Date = Date()) -> [String: Any]? {
        let storedAt = defaults.double(forKey: semanticStateTimestampKey)
        let age = now.timeIntervalSince1970 - storedAt
        guard storedAt > 0, age >= -300, age <= shortConversationTTL,
              let data = defaults.data(forKey: semanticStateKey), data.count <= 65_536 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func snapshot(system: DigitalWellnessV3System) -> [String: Any] {
        var payload: [String: Any] = [
            "last_prompt": "",
            "last_intent": defaults.string(forKey: lastIntentKey) ?? "",
            "last_plan_title": defaults.string(forKey: lastPlanTitleKey) ?? "",
            "last_plan_applied_at": defaults.double(forKey: lastPlanAppliedAtKey),
            "last_plan_outcome": lastPlanOutcome(system: system),
            "main_apps": rememberedMainApps(),
            "weak_hours": rememberedWeakHours(system: system),
            "pattern_cluster": rememberedPatternCluster(),
            "protected_minutes_since_plan": max(0, system.profile.weeklyProtectedMinutes - defaults.integer(forKey: lastPlanProtectedMinutesKey)),
            "breaks_since_plan": max(0, system.profile.weeklyBreakCount - defaults.integer(forKey: lastPlanBreakCountKey))
        ]
        if let bedtime = rememberedBedtimeMinute() {
            payload["bedtime_minute"] = bedtime
        }
        return payload
    }

    static func rememberedMainApps() -> [String] {
        (defaults.string(forKey: mainAppsKey) ?? "")
            .split(separator: "|")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func rememberedBedtimeMinute() -> Int? {
        guard defaults.object(forKey: bedtimeMinuteKey) != nil else { return nil }
        let value = defaults.integer(forKey: bedtimeMinuteKey)
        return (0...(24 * 60 - 1)).contains(value) ? value : nil
    }

    static func rememberedPatternCluster() -> String {
        defaults.string(forKey: patternClusterKey) ?? ""
    }

    static func rememberedWeakHours(system: DigitalWellnessV3System) -> [Int] {
        let candidates = ([system.profile.weakestWindow] + system.weakWindows.map(\.hour))
            .compactMap { $0 }
            .filter { (0...23).contains($0) }
        var seen = Set<Int>()
        var hours: [Int] = []
        for candidate in candidates where !seen.contains(candidate) {
            seen.insert(candidate)
            hours.append(candidate)
            if hours.count == 3 { break }
        }
        return hours
    }

    static func lastPlanOutcome(system: DigitalWellnessV3System) -> String {
        guard defaults.object(forKey: lastPlanAppliedAtKey) != nil else { return "none" }
        let breaksSincePlan = system.profile.weeklyBreakCount - defaults.integer(forKey: lastPlanBreakCountKey)
        let protectedSincePlan = system.profile.weeklyProtectedMinutes - defaults.integer(forKey: lastPlanProtectedMinutesKey)
        if breaksSincePlan > 0 { return "broke" }
        if protectedSincePlan >= 15 { return "held" }
        return "pending"
    }

}
