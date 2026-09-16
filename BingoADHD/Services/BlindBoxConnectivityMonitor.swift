import Foundation
import Network

enum BlindBoxConnectivityStatus: Equatable, Sendable {
    case checking
    case online
    case offline

    var canMakeNetworkRequests: Bool {
        self == .online
    }

    var unavailableMessage: String {
        switch self {
        case .checking:
            return L10n.tr("Checking your connection. Please try again.", zhHans: "正在检查网络连接，请稍后重试。", zhHant: "正在檢查網路連線，請稍後重試。", ja: "接続を確認しています。しばらくしてから再試行してください。")
        case .offline:
            return L10n.tr("You're offline. Connect to the internet and try again.", zhHans: "当前无网络连接，请联网后重试。", zhHant: "目前沒有網路連線，請連線後再試。", ja: "オフラインです。インターネットに接続してから再試行してください。")
        case .online:
            return ""
        }
    }
}

/// A lightweight UI gate only. The eventual CloudKit repository remains the
/// authority for iCloud account state and transport failures; this monitor just
/// prevents an avoidable offline attempt from starting an opening animation.
@MainActor
final class BlindBoxConnectivityMonitor: ObservableObject {
    @Published private(set) var status: BlindBoxConnectivityStatus

    private let monitor: NWPathMonitor?

    init(forceOffline: Bool = false) {
        guard !forceOffline else {
            status = .offline
            monitor = nil
            return
        }

        status = .checking
        let pathMonitor = NWPathMonitor()
        monitor = pathMonitor
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let status: BlindBoxConnectivityStatus = path.status == .satisfied ? .online : .offline
            Task { @MainActor [weak self] in
                self?.status = status
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.bingodays.blindbox.connectivity"))
    }

    deinit {
        monitor?.cancel()
    }
}
