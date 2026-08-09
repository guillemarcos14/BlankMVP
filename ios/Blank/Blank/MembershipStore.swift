import Combine
import Foundation

@MainActor
final class MembershipStore: ObservableObject {
    @Published private(set) var status: MembershipStatus
    @Published private(set) var plan: MembershipPlan
    @Published private(set) var activationCode: String?
    @Published private(set) var maxDevices: Int
    @Published private(set) var validUntil: Date?
    @Published private(set) var lastValidatedAt: Date?
    @Published private(set) var isChecking: Bool = false
    @Published var message: String?

    private let defaults: UserDefaults
    private let client: MembershipClient
    private let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        client: MembershipClient = MembershipClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.client = client
        self.now = now
        status = MembershipStatus(rawValue: defaults.string(forKey: Keys.status) ?? "") ?? .locked
        plan = MembershipPlan(rawValue: defaults.string(forKey: Keys.plan) ?? "") ?? .unknown
        activationCode = defaults.string(forKey: Keys.activationCode)
        maxDevices = max(1, defaults.integer(forKey: Keys.maxDevices))
        validUntil = Self.date(forKey: Keys.validUntil, defaults: defaults)
        lastValidatedAt = Self.date(forKey: Keys.lastValidatedAt, defaults: defaults)
    }

    var appInstallId: String {
        if let existing = defaults.string(forKey: Keys.appInstallId), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: Keys.appInstallId)
        return created
    }

    var hasAccess: Bool {
        guard status.grantsAccess else { return false }
        guard let validUntil, now() <= validUntil else { return false }
        if let lastValidatedAt, now().timeIntervalSince(lastValidatedAt) > Self.localValidationTTL {
            return false
        }
        return true
    }

    var accessLabel: String {
        switch status {
        case .trialActive:
            return "Prueba activa"
        case .active:
            return plan.displayName
        case .pastDue:
            return "Pago pendiente"
        case .cancelled:
            return "Membresía cancelada"
        case .expired:
            return "Membresía expirada"
        case .locked:
            return "Membresía requerida"
        }
    }

    func redeem(code rawCode: String) async {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count >= 6 else {
            message = "Introduce un código válido."
            return
        }

        isChecking = true
        message = nil
        defer { isChecking = false }

        do {
            let entitlement = try await client.redeem(code: code, appInstallId: appInstallId)
            apply(entitlement: entitlement, activationCode: code)
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func refreshIfNeeded(force: Bool = false) async {
        guard let activationCode else { return }
        if !force, let lastValidatedAt, now().timeIntervalSince(lastValidatedAt) < Self.minimumRefreshInterval {
            return
        }

        isChecking = true
        defer { isChecking = false }

        do {
            let entitlement = try await client.status(code: activationCode, appInstallId: appInstallId)
            apply(entitlement: entitlement, activationCode: activationCode)
            message = nil
        } catch {
            if !hasAccess {
                message = error.localizedDescription
            }
        }
    }

    func resetLocalActivation() {
        activationCode = nil
        status = .locked
        plan = .unknown
        maxDevices = 1
        validUntil = nil
        lastValidatedAt = nil
        message = nil
        persist()
    }

    #if DEBUG
    #if targetEnvironment(simulator)
    func grantSimulatorAccess() {
        apply(
            entitlement: MembershipEntitlement(
                status: .active,
                plan: .annual,
                maxDevices: 1,
                validUntil: now().addingTimeInterval(365 * 24 * 60 * 60)
            ),
            activationCode: "SIMULATOR-ACCESS"
        )
        message = nil
    }
    #endif
    #endif

    private func apply(entitlement: MembershipEntitlement, activationCode: String) {
        self.activationCode = activationCode
        status = entitlement.status
        plan = entitlement.plan
        maxDevices = max(1, entitlement.maxDevices)
        validUntil = entitlement.validUntil
        lastValidatedAt = now()
        persist()
    }

    private func persist() {
        defaults.set(status.rawValue, forKey: Keys.status)
        defaults.set(plan.rawValue, forKey: Keys.plan)
        defaults.set(activationCode, forKey: Keys.activationCode)
        defaults.set(maxDevices, forKey: Keys.maxDevices)
        defaults.set(validUntil?.timeIntervalSince1970, forKey: Keys.validUntil)
        defaults.set(lastValidatedAt?.timeIntervalSince1970, forKey: Keys.lastValidatedAt)
    }

    private static func date(forKey key: String, defaults: UserDefaults) -> Date? {
        guard let timestamp = defaults.object(forKey: key) as? TimeInterval, timestamp > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    private enum Keys {
        static let appInstallId = "blankMembershipAppInstallId"
        static let activationCode = "blankMembershipActivationCode"
        static let status = "blankMembershipStatus"
        static let plan = "blankMembershipPlan"
        static let maxDevices = "blankMembershipMaxDevices"
        static let validUntil = "blankMembershipValidUntil"
        static let lastValidatedAt = "blankMembershipLastValidatedAt"
    }

    private static let localValidationTTL: TimeInterval = 72 * 60 * 60
    private static let minimumRefreshInterval: TimeInterval = 15 * 60
}

enum MembershipStatus: String, Codable {
    case locked
    case trialActive = "trial_active"
    case active
    case pastDue = "past_due"
    case cancelled
    case expired

    init(apiValue: String) {
        let normalized = apiValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        self = MembershipStatus(rawValue: normalized) ?? .locked
    }

    var grantsAccess: Bool {
        switch self {
        case .trialActive, .active:
            return true
        case .locked, .pastDue, .cancelled, .expired:
            return false
        }
    }
}

enum MembershipPlan: String, Codable {
    case unknown
    case trial
    case monthly
    case annual
    case family

    init(apiValue: String?) {
        let normalized = (apiValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if normalized.contains("trial") || normalized.contains("prueba") {
            self = .trial
        } else if normalized.contains("monthly") || normalized.contains("mensual") || normalized.contains("mes") {
            self = .monthly
        } else if normalized.contains("family") || normalized.contains("familiar") {
            self = .family
        } else if normalized.contains("annual") || normalized.contains("anual") || normalized.contains("ano") || normalized.contains("year") {
            self = .annual
        } else {
            self = MembershipPlan(rawValue: normalized) ?? .unknown
        }
    }

    var displayName: String {
        switch self {
        case .trial:
            return "Plan de prueba"
        case .monthly:
            return "Membresía mensual"
        case .annual:
            return "Membresía anual"
        case .family:
            return "Membresía familiar"
        case .unknown:
            return "Membresía Blank"
        }
    }
}

struct MembershipEntitlement {
    let status: MembershipStatus
    let plan: MembershipPlan
    let maxDevices: Int
    let validUntil: Date?
}

struct MembershipClient {
    private let baseURL: URL?
    private let session: URLSession

    init(
        baseURL: URL? = MembershipClient.configuredBaseURL(),
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func redeem(code: String, appInstallId: String) async throws -> MembershipEntitlement {
        #if DEBUG
        if baseURL == nil {
            return Self.debugEntitlement(for: code)
        }
        #endif
        return try await request(path: "redeem-code", code: code, appInstallId: appInstallId)
    }

    func status(code: String, appInstallId: String) async throws -> MembershipEntitlement {
        #if DEBUG
        if baseURL == nil {
            return Self.debugEntitlement(for: code)
        }
        #endif
        return try await request(path: "membership-status", code: code, appInstallId: appInstallId)
    }

    private func request(path: String, code: String, appInstallId: String) async throws -> MembershipEntitlement {
        guard let baseURL else {
            throw MembershipClientError.missingEndpoint
        }

        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(code: code, app_install_id: appInstallId))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            Self.debugLog(path: path, message: "Invalid non-HTTP response")
            throw MembershipClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            Self.debugLog(path: path, statusCode: httpResponse.statusCode, data: data, message: "Rejected activation response")
            throw MembershipClientError.rejectedCode
        }

        do {
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            return try decoded.entitlement()
        } catch {
            Self.debugLog(path: path, statusCode: httpResponse.statusCode, data: data, message: "Could not decode activation response: \(error)")
            throw MembershipClientError.invalidResponse
        }
    }

    private static func debugLog(path: String, statusCode: Int? = nil, data: Data? = nil, message: String) {
        #if DEBUG
        let statusText = statusCode.map { " status=\($0)" } ?? ""
        let bodyText = data
            .flatMap { String(data: $0, encoding: .utf8) }
            .map { " body=\($0)" } ?? ""
        print("[BlankMembership] \(path)\(statusText) \(message)\(bodyText)")
        #endif
    }

    private static func configuredBaseURL() -> URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "BlankMembershipAPIBaseURL") as? String else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }
        return URL(string: trimmed)
    }

    #if DEBUG
    private static func debugEntitlement(for code: String) -> MembershipEntitlement {
        let uppercased = code.uppercased()
        let plan: MembershipPlan
        let status: MembershipStatus
        let maxDevices: Int
        let validUntil: Date

        if uppercased.hasPrefix("TRIAL") {
            plan = .trial
            status = .trialActive
            maxDevices = 1
            validUntil = Date().addingTimeInterval(30 * 24 * 60 * 60)
        } else if uppercased.hasPrefix("MONTHLY") {
            plan = .monthly
            status = .active
            maxDevices = 1
            validUntil = Date().addingTimeInterval(30 * 24 * 60 * 60)
        } else if uppercased.hasPrefix("FAMILY") {
            plan = .family
            status = .active
            maxDevices = 5
            validUntil = Date().addingTimeInterval(365 * 24 * 60 * 60)
        } else {
            plan = .annual
            status = .active
            maxDevices = 1
            validUntil = Date().addingTimeInterval(365 * 24 * 60 * 60)
        }

        return MembershipEntitlement(
            status: status,
            plan: plan,
            maxDevices: maxDevices,
            validUntil: validUntil
        )
    }
    #endif

    private struct RequestBody: Encodable {
        let code: String
        let app_install_id: String
    }

    private struct ResponseBody: Decodable {
        let status: String
        let plan: String?
        let maxDevices: Int?
        let trialEndsAt: String?
        let currentPeriodEndsAt: String?

        enum CodingKeys: String, CodingKey {
            case status
            case plan
            case maxDevices = "max_devices"
            case trialEndsAt = "trial_ends_at"
            case currentPeriodEndsAt = "current_period_ends_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decode(String.self, forKey: .status)
            plan = try container.decodeIfPresent(String.self, forKey: .plan)
            trialEndsAt = try container.decodeIfPresent(String.self, forKey: .trialEndsAt)
            currentPeriodEndsAt = try container.decodeIfPresent(String.self, forKey: .currentPeriodEndsAt)

            if let value = try? container.decodeIfPresent(Int.self, forKey: .maxDevices) {
                maxDevices = value
            } else if let value = try? container.decodeIfPresent(String.self, forKey: .maxDevices) {
                maxDevices = Int(value)
            } else {
                maxDevices = nil
            }
        }

        func entitlement() throws -> MembershipEntitlement {
            let decodedStatus = MembershipStatus(apiValue: status)
            let decodedPlan = MembershipPlan(apiValue: plan)
            let validUntil = Self.parseFirstValidDate([trialEndsAt, currentPeriodEndsAt])
                ?? Self.fallbackValidUntil(for: decodedStatus, plan: decodedPlan)

            return MembershipEntitlement(
                status: decodedStatus,
                plan: decodedPlan,
                maxDevices: maxDevices ?? 1,
                validUntil: validUntil
            )
        }

        private static func parseFirstValidDate(_ values: [String?]) -> Date? {
            for value in values.compactMap({ $0 }) {
                if let date = isoDateFormatter.date(from: value) ?? isoDateFormatterWithFractionalSeconds.date(from: value) {
                    return date
                }
            }
            return nil
        }

        private static func fallbackValidUntil(for status: MembershipStatus, plan: MembershipPlan) -> Date? {
            guard status.grantsAccess else { return nil }

            switch plan {
            case .trial:
                return Date().addingTimeInterval(30 * 24 * 60 * 60)
            case .monthly:
                return Date().addingTimeInterval(30 * 24 * 60 * 60)
            case .annual, .family, .unknown:
                return Date().addingTimeInterval(365 * 24 * 60 * 60)
            }
        }

        private static let isoDateFormatter = ISO8601DateFormatter()

        private static let isoDateFormatterWithFractionalSeconds: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
    }
}

enum MembershipClientError: LocalizedError {
    case missingEndpoint
    case invalidResponse
    case rejectedCode

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return "No se ha configurado el servidor de membresía."
        case .invalidResponse:
            return "No hemos podido validar la membresía."
        case .rejectedCode:
            return "Este código no es válido o ya no está activo."
        }
    }
}
