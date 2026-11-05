import SwiftUI
import GoogleCast

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let criteria = GCKDiscoveryCriteria(applicationID: ReceiverConfiguration.applicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.suspendSessionsWhenBackgrounded = false
        GCKCastContext.setSharedInstanceWith(options)
        GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true
        return true
    }
}

@main struct CastRemoteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var controller = CastController()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(controller)
                .onOpenURL { controller.open($0) }
                .onAppear {
                    controller.refreshConnection()
#if CAST_ENGINE_TESTING
                    if ProcessInfo.processInfo.environment["CAST_ENGINE_SELFTEST"] == "1" { Task { await NativeEngineValidation.run() } }
#endif
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { controller.refreshConnection();StremioSync.shared.flush() }
                    else { controller.savePlaybackPosition(phase:phase == .inactive ? "inactive":"background") }
                }
        }
    }
}

struct CastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        let button = GCKUICastButton(frame: .zero)
        button.tintColor = .white
        return button
    }
    func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
}


