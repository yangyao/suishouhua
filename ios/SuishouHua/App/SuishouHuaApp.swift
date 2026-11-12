import SwiftUI
import UIKit

// MARK: - 方向控制：未连接竖屏、已连接锁定横屏

enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait

    static func set(_ mask: UIInterfaceOrientationMask) {
        guard Self.mask != mask else { return }
        Self.mask = mask
        DispatchQueue.main.async {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            for scene in scenes {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
                scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

// MARK: - 应用入口

@main
struct SuishouHuaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.screen {
            case .home: HomeView()
            case .scan: ScanView()
            case .manual: ManualPairView()
            case .canvas: CanvasScreen()
            }
        }
        .background(Theme.background)
    }
}
