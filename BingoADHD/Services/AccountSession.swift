import Foundation
import SwiftUI
import UIKit
import ObjectiveC
import CryptoKit
import AuthenticationServices
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn

struct AccountProfile: Codable, Equatable {
    let uid: String
    let displayName: String?
    let email: String?
    let photoURL: String?
    let providerIDs: [String]

    init(user: User) {
        uid = user.uid
        displayName = user.displayName
        email = user.email
        photoURL = user.photoURL?.absoluteString
        providerIDs = user.providerData.map(\.providerID)
    }
}

struct AccountSnapshot: Codable {
    let version: Int
    var profile: AccountProfile
    var updatedAt: Date
    var themeRawValue: String?
    var hasSeenOnboarding: Bool
    var hapticsEnabled: Bool
    var soundEffectsEnabled: Bool
    var board: SavedBoard?
    var boardLastSavedAt: Date?
    var boardCountdownEndsAt: Date?
    var firstSeenDate: Date?
    var tasksLibrary: MyTasksLibrary
    var rewards: [CustomReward]
    var stickerInventory: [String: Int]
    var stickerPlacements: [HomeStickerPlacement]
    var totalPoints: Int?
    var lifetimePoints: Int?
    var dailyRewardState: DailyRewardState?
    var diaryEntries: [String: BingoDiaryEntry]
    var timeoutPayload: [String: [String: Int]]
}

enum AccountAuthPhase: Equatable {
    case loading
    case signedOut
    case signedIn
}

enum AccountSessionError: LocalizedError {
    case missingPresentationContext
    case missingGoogleClientID
    case missingGoogleTokens
    case appleCredentialMissing
    case unsupportedGoogleConfiguration

    var errorDescription: String? {
        switch self {
        case .missingPresentationContext:
            return "Unable to find a presentation window for sign-in."
        case .missingGoogleClientID:
            return "Google Sign-In is not configured. Add CLIENT_ID and REVERSED_CLIENT_ID to GoogleService-Info.plist."
        case .missingGoogleTokens:
            return "Google Sign-In did not return valid credentials."
        case .appleCredentialMissing:
            return "Apple Sign-In did not return a valid identity token."
        case .unsupportedGoogleConfiguration:
            return "Google Sign-In still needs a valid URL scheme in the app configuration."
        }
    }
}

private enum AccountStorageKeys {
    static let activeAccountUID = "active_account_uid_v1"
    static let installMarker = "local_install_marker_v1"
}

@MainActor
final class AccountSession: NSObject, ObservableObject {
    static let shared = AccountSession()

    @Published private(set) var phase: AccountAuthPhase = .loading
    @Published private(set) var profile: AccountProfile?
    @Published private(set) var isPerformingAuth = false
    @Published var errorMessage: String?

    private let syncService = AccountSyncService()
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var pendingSyncTask: Task<Void, Never>?
    private var isApplyingRemoteSnapshot = false
    private var userDefaultsObserver: NSObjectProtocol?

    private override init() {
        super.init()
        guard AppFeatureFlags.isAccountEnabled else {
            forceSignOutForSoftOffMode()
            phase = .signedOut
            profile = nil
            return
        }

        handleFreshInstallAuthenticationResetIfNeeded()
        userDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleUserDefaultsChange()
            }
        }
        startAuthListener()
    }

    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
        if let userDefaultsObserver {
            NotificationCenter.default.removeObserver(userDefaultsObserver)
        }
    }

    var isAuthenticated: Bool {
        profile != nil
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        guard AppFeatureFlags.isAccountEnabled else { return }
        guard phase != .active else { return }
        scheduleSync(immediate: true)
    }

    func clearError() {
        errorMessage = nil
    }

    func signInWithApple() async {
        guard AppFeatureFlags.isAccountEnabled else { return }
        guard !isPerformingAuth else { return }
        isPerformingAuth = true
        errorMessage = nil

        do {
            let rawNonce = Self.randomNonce()
            let credential = try await AppleSignInCoordinator.requestCredential(rawNonce: rawNonce)
            guard let identityToken = credential.identityToken,
                  let idTokenString = String(data: identityToken, encoding: .utf8) else {
                throw AccountSessionError.appleCredentialMissing
            }

            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: rawNonce,
                fullName: credential.fullName
            )

            _ = try await Auth.auth().signIn(with: firebaseCredential)
        } catch {
            let message = userFacingAuthError(error)
            errorMessage = message.isEmpty ? nil : message
        }

        isPerformingAuth = false
    }

    func signInWithGoogle() async {
        guard AppFeatureFlags.isAccountEnabled else { return }
        guard !isPerformingAuth else { return }
        isPerformingAuth = true
        errorMessage = nil

        do {
            do {
                try await performGoogleSignIn(forceRefresh: true)
            } catch {
                if shouldRetryGoogleSignIn(error) {
                    try await performGoogleSignIn(forceRefresh: true)
                } else {
                    throw error
                }
            }
        } catch {
            let message = userFacingAuthError(error)
            errorMessage = message.isEmpty ? nil : message
        }

        isPerformingAuth = false
    }

    func signOut() {
        pendingSyncTask?.cancel()
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            profile = nil
            phase = .signedOut
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func forceSignOutForSoftOffMode() {
        pendingSyncTask?.cancel()
        UserDefaults.standard.removeObject(forKey: AccountStorageKeys.activeAccountUID)
        do {
            try Auth.auth().signOut()
        } catch {
            // Ignore sign-out failures in soft-off mode.
        }
        GIDSignIn.sharedInstance.signOut()
    }

    private func handleUserDefaultsChange() {
        guard isAuthenticated, !isApplyingRemoteSnapshot else { return }
        scheduleSync()
    }

    private func handleFreshInstallAuthenticationResetIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AccountStorageKeys.installMarker) == false else { return }

        defaults.set(true, forKey: AccountStorageKeys.installMarker)
        do {
            try Auth.auth().signOut()
        } catch {
            // Ignore fresh-install sign-out failures; login flow remains available.
        }
        GIDSignIn.sharedInstance.signOut()
    }

    private func startAuthListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                await self?.handleAuthChange(user)
            }
        }
    }

    private func handleAuthChange(_ user: User?) async {
        pendingSyncTask?.cancel()

        guard let user else {
            profile = nil
            phase = .signedOut
            return
        }

        let currentProfile = AccountProfile(user: user)
        profile = currentProfile
        phase = .signedIn

        do {
            try await syncService.restoreOrBootstrapAccount(for: currentProfile)
            scheduleSync(immediate: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleSync(immediate: Bool = false) {
        pendingSyncTask?.cancel()
        guard let profile else { return }

        pendingSyncTask = Task { [syncService] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
            guard !Task.isCancelled else { return }

            do {
                try await syncService.uploadCurrentState(for: profile)
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    fileprivate func applyRemoteSnapshot(_ snapshot: AccountSnapshot) {
        isApplyingRemoteSnapshot = true
        defer { isApplyingRemoteSnapshot = false }

        if let themeRawValue = snapshot.themeRawValue {
            UserDefaults.standard.set(themeRawValue, forKey: AppSettings.themeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppSettings.themeKey)
        }
        // Keep onboarding visibility local to the current install/device.
        UserDefaults.standard.set(snapshot.hapticsEnabled, forKey: AppSettings.hapticsEnabledKey)
        UserDefaults.standard.set(snapshot.soundEffectsEnabled, forKey: AppSettings.soundEffectsEnabledKey)

        if let board = snapshot.board {
            BingoBoardStore.saveBoard(board, savedAt: snapshot.boardLastSavedAt ?? snapshot.updatedAt)
        } else {
            BingoBoardStore.clearBoard()
        }
        BingoBoardStore.saveBoardCountdownEndsAt(snapshot.boardCountdownEndsAt)
        if let firstSeenDate = snapshot.firstSeenDate {
            BingoBoardStore.setFirstSeenDate(firstSeenDate)
        }

        CommonTasksStore.saveLibrary(snapshot.tasksLibrary)
        RewardStore.saveRewards(snapshot.rewards)
        StickerStore.saveInventoryCounts(snapshot.stickerInventory.reduce(into: [StickerKind: Int]()) { partial, entry in
            guard let kind = StickerKind(rawValue: entry.key) else { return }
            partial[kind] = entry.value
        })
        StickerStore.savePlacements(snapshot.stickerPlacements)

        if let totalPoints = snapshot.totalPoints {
            PointsStore.saveTotalPoints(totalPoints)
        } else {
            PointsStore.clearTotalPoints()
        }
        if let lifetimePoints = snapshot.lifetimePoints {
            PointsStore.saveLifetimePoints(lifetimePoints)
        } else {
            PointsStore.clearLifetimePoints()
        }
        if let dailyRewardState = snapshot.dailyRewardState {
            PointsStore.saveDailyRewardState(dailyRewardState)
        } else {
            PointsStore.clearDailyRewardState()
        }

        BingoDiaryStore.replaceAllEntriesDictionary(snapshot.diaryEntries)
        BingoTimeoutStore.replacePayload(snapshot.timeoutPayload)
        AnalyticsService.bootstrap()
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms = (0..<16).map { _ in UInt8.random(in: 0...255) }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private static func requestGoogleUser(with rootViewController: UIViewController) async throws -> GIDSignInResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDSignInResult, Error>) in
            GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result else {
                    continuation.resume(throwing: AccountSessionError.missingGoogleTokens)
                    return
                }

                continuation.resume(returning: result)
            }
        }
    }

    private func performGoogleSignIn(forceRefresh: Bool) async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AccountSessionError.missingGoogleClientID
        }
        guard let rootViewController = UIApplication.shared.topViewController else {
            throw AccountSessionError.missingPresentationContext
        }

        if forceRefresh {
            GIDSignIn.sharedInstance.signOut()
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await Self.requestGoogleUser(with: rootViewController)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AccountSessionError.missingGoogleTokens
        }

        let accessToken = result.user.accessToken.tokenString
        let firebaseCredential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        _ = try await Auth.auth().signIn(with: firebaseCredential)
    }

    private func shouldRetryGoogleSignIn(_ error: Error) -> Bool {
        let nsError = error as NSError
        let message = ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription).lowercased()

        if message.contains("id token expired") || message.contains("token expired") || message.contains("has expired") {
            return true
        }

        if nsError.domain == AuthErrorDomain, let authCode = AuthErrorCode(rawValue: nsError.code) {
            if authCode == .invalidCredential, message.contains("expired") {
                return true
            }
        }

        return false
    }

    private func userFacingAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        let fallback = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

        #if DEBUG
        print("[AccountSession] Auth error:", nsError.domain, nsError.code, fallback)
        #endif

        if nsError.domain == ASAuthorizationError.errorDomain,
           let appleCode = ASAuthorizationError.Code(rawValue: nsError.code),
           appleCode == .canceled {
            return ""
        }

        if nsError.domain == AuthErrorDomain, let authCode = AuthErrorCode(rawValue: nsError.code) {
            switch authCode {
            case .operationNotAllowed:
                return "Firebase Authentication 尚未启用该登录方式。请到 Firebase Console > Authentication > Sign-in method 启用 Apple 和 Google 后再试。"
            case .invalidCredential, .invalidCustomToken, .customTokenMismatch:
                if fallback.localizedCaseInsensitiveContains("expired") {
                    return "登录凭证已过期。已自动重试过一次；请确保设备“日期与时间”为自动，并重新发起登录。"
                }
                return "登录凭证无效。请检查 Firebase 配置、Bundle ID 与 Apple/Google 登录配置是否一致。"
            default:
                break
            }
        }

        if fallback.localizedCaseInsensitiveContains("identity provider configuration is not found") {
            return "身份提供商配置缺失。请在 Firebase Console > Authentication > Sign-in method 中开启并正确配置 Apple 与 Google 登录。"
        }

        return fallback
    }
}

private actor AccountSyncService {
    private enum FirestoreFields {
        static let snapshotJSON = "snapshot_json"
        static let version = "version"
        static let updatedAt = "updated_at"
    }

    private let db = Firestore.firestore()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func restoreOrBootstrapAccount(for profile: AccountProfile) async throws {
        let previousUID = UserDefaults.standard.string(forKey: AccountStorageKeys.activeAccountUID)
        let reference = db.collection("users").document(profile.uid)
        let snapshot = try await reference.getDocument()

        if let data = snapshot.data(), let remoteSnapshot = try decodeSnapshot(from: data) {
            if let previousUID, previousUID != profile.uid {
                await MainActor.run {
                    Self.resetLocalAccountState()
                }
            }
            await MainActor.run {
                AccountSession.shared.applyRemoteSnapshot(remoteSnapshot)
            }
            UserDefaults.standard.set(profile.uid, forKey: AccountStorageKeys.activeAccountUID)
            try await uploadCurrentState(for: profile)
        } else {
            if let previousUID, previousUID != profile.uid {
                await MainActor.run {
                    Self.resetLocalAccountState()
                }
            }
            UserDefaults.standard.set(profile.uid, forKey: AccountStorageKeys.activeAccountUID)
            try await uploadCurrentState(for: profile)
        }
    }

    func uploadCurrentState(for profile: AccountProfile) async throws {
        let payload = try encodeSnapshot(Self.makeLocalSnapshot(for: profile), using: encoder)
        try await db.collection("users").document(profile.uid).setData(payload, merge: true)
    }

    private func decodeSnapshot(from payload: [String: Any]) throws -> AccountSnapshot? {
        if let snapshotJSONString = payload[FirestoreFields.snapshotJSON] as? String,
           let data = snapshotJSONString.data(using: .utf8) {
            return try decoder.decode(AccountSnapshot.self, from: data)
        }

        guard JSONSerialization.isValidJSONObject(payload) else { return nil }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return try decoder.decode(AccountSnapshot.self, from: data)
    }

    private func encodeSnapshot(_ snapshot: AccountSnapshot, using encoder: JSONEncoder) throws -> [String: Any] {
        let data = try encoder.encode(snapshot)
        guard let snapshotJSONString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "AccountSyncService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize account snapshot."])
        }

        return [
            FirestoreFields.snapshotJSON: snapshotJSONString,
            FirestoreFields.version: snapshot.version,
            FirestoreFields.updatedAt: Timestamp(date: snapshot.updatedAt)
        ]
    }

    private static func makeLocalSnapshot(for profile: AccountProfile) -> AccountSnapshot {
        AccountSnapshot(
            version: 1,
            profile: profile,
            updatedAt: Date(),
            themeRawValue: UserDefaults.standard.string(forKey: AppSettings.themeKey),
            hasSeenOnboarding: UserDefaults.standard.bool(forKey: AppSettings.hasSeenOnboardingKey),
            hapticsEnabled: AppSettings.isHapticsEnabled,
            soundEffectsEnabled: AppSettings.isSoundEffectsEnabled,
            board: BingoBoardStore.loadBoard(),
            boardLastSavedAt: BingoBoardStore.loadBoardLastSavedAt(),
            boardCountdownEndsAt: BingoBoardStore.loadBoardCountdownEndsAt(),
            firstSeenDate: BingoBoardStore.firstSeenDate(),
            tasksLibrary: CommonTasksStore.loadLibrary(),
            rewards: RewardStore.loadRewards(),
            stickerInventory: StickerStore.loadInventoryCounts().reduce(into: [String: Int]()) { partial, entry in
                partial[entry.key.rawValue] = entry.value
            },
            stickerPlacements: StickerStore.loadPlacements(),
            totalPoints: PointsStore.loadTotalPoints(),
            lifetimePoints: PointsStore.loadLifetimePoints(),
            dailyRewardState: PointsStore.loadDailyRewardState(),
            diaryEntries: BingoDiaryStore.loadAllEntriesDictionary(),
            timeoutPayload: BingoTimeoutStore.loadAllPayload()
        )
    }

    @MainActor
    private static func resetLocalAccountState() {
        UserDefaults.standard.removeObject(forKey: AppSettings.themeKey)
        UserDefaults.standard.removeObject(forKey: AppSettings.hasSeenOnboardingKey)
        UserDefaults.standard.removeObject(forKey: AppSettings.hapticsEnabledKey)
        UserDefaults.standard.removeObject(forKey: AppSettings.soundEffectsEnabledKey)

        BingoBoardStore.clearBoard()
        BingoBoardStore.clearFirstSeenDate()
        CommonTasksStore.saveLibrary(MyTasksLibrary())
        RewardStore.clearRewards()
        StickerStore.clearInventoryCounts()
        StickerStore.clearPlacements()
        PointsStore.clearTotalPoints()
        PointsStore.clearLifetimePoints()
        PointsStore.clearDailyRewardState()
        BingoDiaryStore.replaceAllEntriesDictionary([:])
        BingoTimeoutStore.replacePayload([:])
    }
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let rawNonce: String
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    private init(rawNonce: String) {
        self.rawNonce = rawNonce
    }

    static func requestCredential(rawNonce: String) async throws -> ASAuthorizationAppleIDCredential {
        let coordinator = AppleSignInCoordinator(rawNonce: rawNonce)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>) in
            coordinator.continuation = continuation
            coordinator.start()
            let key = UnsafeRawPointer(Unmanaged.passUnretained(coordinator).toOpaque())
            objc_setAssociatedObject(
                UIApplication.shared,
                key,
                coordinator,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { releaseSelf() }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AccountSessionError.appleCredentialMissing)
            return
        }
        continuation?.resume(returning: credential)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        defer { releaseSelf() }
        continuation?.resume(throwing: error)
    }

    private func start() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(rawNonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    private func releaseSelf() {
        let key = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        objc_setAssociatedObject(UIApplication.shared, key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        continuation = nil
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

private extension UIApplication {
    var topViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .topMostViewController()
    }
}

private extension UIViewController {
    func topMostViewController() -> UIViewController {
        if let presentedViewController {
            return presentedViewController.topMostViewController()
        }
        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.topMostViewController() ?? navigationController
        }
        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.topMostViewController() ?? tabBarController
        }
        return self
    }
}
