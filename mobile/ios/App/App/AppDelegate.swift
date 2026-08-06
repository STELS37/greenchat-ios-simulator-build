import UIKit
import Capacitor
import WebKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UITabBarDelegate, WKScriptMessageHandler {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        gcInstallPrivacyShield()
        gcInstallLiquidGlassTabBarIfAvailable()
        #if DEBUG
        // GC_IOS_SIMULATOR_MEDIA_PROBE
        GCSimulatorMediaProbe.runIfRequested()
        #endif
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Called when the app was launched with a url. Feel free to add additional processing here,
        // but if you want the App API to support tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Called when the app was launched with an activity, including Universal Links.
        // Feel free to add additional processing here, but if you want the App API to support
        // tracking app url opens, make sure to keep this call
        return ApplicationDelegateProxy.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }


    // GC_T530_PRIVACY_SHIELD
    private static let gcPrivacyShieldTag = 0x47435348

    private func gcInstallPrivacyShield() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(gcShowPrivacyShield), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(gcHidePrivacyShield), name: UIApplication.didBecomeActiveNotification, object: nil)
        gcExcludeApplicationDataFromBackup()
    }

    @objc private func gcShowPrivacyShield() {
        guard let window = self.window else { return }
        if window.viewWithTag(Self.gcPrivacyShieldTag) != nil { return }
        let shield = UIView(frame: window.bounds)
        shield.tag = Self.gcPrivacyShieldTag
        shield.backgroundColor = UIColor.black
        shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let label = UILabel(frame: shield.bounds)
        label.text = "Green Chat"
        label.textColor = UIColor.white
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        shield.addSubview(label)
        window.addSubview(shield)
    }

    @objc private func gcHidePrivacyShield() {
        self.window?.viewWithTag(Self.gcPrivacyShieldTag)?.removeFromSuperview()
    }

    private func gcExcludeApplicationDataFromBackup() {
        let manager = FileManager.default
        let directories: [FileManager.SearchPathDirectory] = [.applicationSupportDirectory, .documentDirectory, .cachesDirectory]
        for directory in directories {
            guard var url = manager.urls(for: directory, in: .userDomainMask).first else { continue }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
    }


    // GC_IOS26_LIQUID_GLASS_TAB_BAR
    private weak var gcLiquidGlassTabBar: UITabBar?
    private weak var gcLiquidGlassBridgeController: CAPBridgeViewController?
    private var gcLiquidGlassInstallAttempts = 0
    private let gcLiquidGlassRoutes = ["/", "/calls", "/contacts", "/wallet", "/settings"]
    private static let gcLiquidGlassHandler = "gcNativeTabBar"

    private func gcInstallLiquidGlassTabBarIfAvailable() {
        guard #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard gcLiquidGlassTabBar == nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.gcTryInstallLiquidGlassTabBar()
        }
    }

    private func gcTryInstallLiquidGlassTabBar() {
        guard #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard gcLiquidGlassTabBar == nil else { return }
        guard let window = self.window,
              let root = window.rootViewController,
              let bridgeController = gcFindBridgeController(root),
              let webView = bridgeController.bridge?.webView else {
            gcLiquidGlassInstallAttempts += 1
            if gcLiquidGlassInstallAttempts < 40 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.gcTryInstallLiquidGlassTabBar()
                }
            }
            return
        }

        let russian = Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") == true
        let titles = russian
            ? ["Чаты", "Звонки", "Контакты", "Кошелёк", "Ещё"]
            : ["Chats", "Calls", "Contacts", "Wallet", "More"]
        let symbols = ["message.fill", "phone.fill", "person.2.fill", "creditcard.fill", "ellipsis"]
        let tabBar = UITabBar(frame: .zero)
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.delegate = self
        tabBar.tintColor = UIColor.systemGreen
        tabBar.unselectedItemTintColor = UIColor.secondaryLabel
        tabBar.itemPositioning = .fill
        // The owner wants the destinations to float directly above the screen, without the large
        // grey system capsule around the whole row. Keep UIKit's item states, but make the bar's
        // own material, background and separator fully transparent through the public appearance API.
        let transparentAppearance = UITabBarAppearance()
        transparentAppearance.configureWithTransparentBackground()
        transparentAppearance.backgroundColor = UIColor.clear
        transparentAppearance.backgroundEffect = nil
        transparentAppearance.shadowColor = UIColor.clear
        tabBar.standardAppearance = transparentAppearance
        tabBar.scrollEdgeAppearance = transparentAppearance
        tabBar.isTranslucent = true
        tabBar.backgroundColor = UIColor.clear
        tabBar.backgroundImage = UIImage()
        tabBar.shadowImage = UIImage()
        tabBar.layer.backgroundColor = UIColor.clear.cgColor
        tabBar.accessibilityIdentifier = "gc-liquid-glass-tab-bar"
        tabBar.items = titles.indices.map { index in
            UITabBarItem(title: titles[index], image: UIImage(systemName: symbols[index]), tag: index)
        }
        tabBar.selectedItem = tabBar.items?.first
        // The native bar is authenticated shell chrome. Start hidden so the login, public-link,
        // lock and legal-gate screens never flash account navigation before the WebView reports a shell.
        tabBar.isHidden = true
        tabBar.isUserInteractionEnabled = false
        tabBar.accessibilityElementsHidden = true

        bridgeController.view.addSubview(tabBar)
        let safeBottom = max(bridgeController.view.safeAreaInsets.bottom, window.safeAreaInsets.bottom)
        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: bridgeController.view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: bridgeController.view.trailingAnchor),
            tabBar.bottomAnchor.constraint(equalTo: bridgeController.view.bottomAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 50 + safeBottom),
        ])
        bridgeController.view.bringSubviewToFront(tabBar)
        gcLiquidGlassBridgeController = bridgeController
        gcLiquidGlassTabBar = tabBar

        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: Self.gcLiquidGlassHandler)
        controller.add(self, name: Self.gcLiquidGlassHandler)
        let bootstrap = """
        (() => {
          let pending = false;
          const publishNow = () => {
            pending = false;
            const visible = Boolean(document.querySelector('.gc-superapp'));
            const root = document.documentElement;
            if (root) {
              if (visible) root.setAttribute('data-gc-native-tabbar', 'ios26');
              else root.removeAttribute('data-gc-native-tabbar');
            }
            window.webkit?.messageHandlers?.gcNativeTabBar?.postMessage({
              hash: window.location.hash || '#/',
              visible
            });
          };
          const publish = () => {
            if (pending) return;
            pending = true;
            window.requestAnimationFrame(publishNow);
          };
          if (window.__gcNativeTabBarListener) window.removeEventListener('hashchange', window.__gcNativeTabBarListener);
          window.__gcNativeTabBarListener = publish;
          window.addEventListener('hashchange', publish);
          if (window.__gcNativeTabBarObserver) window.__gcNativeTabBarObserver.disconnect();
          window.__gcNativeTabBarObserver = new MutationObserver(publish);
          window.__gcNativeTabBarObserver.observe(document.documentElement, { childList: true, subtree: true });
          publish();
        })();
        """
        controller.addUserScript(WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView.evaluateJavaScript(bootstrap)
    }

    private func gcFindBridgeController(_ controller: UIViewController) -> CAPBridgeViewController? {
        if let bridge = controller as? CAPBridgeViewController { return bridge }
        for child in controller.children {
            if let bridge = gcFindBridgeController(child) { return bridge }
        }
        return nil
    }

    private func gcSetLiquidGlassTabBar(visible: Bool, hash: String) {
        guard let tabBar = gcLiquidGlassTabBar else { return }
        tabBar.isHidden = !visible
        tabBar.isUserInteractionEnabled = visible
        tabBar.accessibilityElementsHidden = !visible
        guard visible else { return }
        gcSelectLiquidGlassTab(for: hash)
        gcLiquidGlassBridgeController?.view.bringSubviewToFront(tabBar)
    }

    private func gcSelectLiquidGlassTab(for hash: String) {
        let path = hash.replacingOccurrences(of: "#", with: "").split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        let index: Int
        if path == "/calls" || path.hasPrefix("/call/") {
            index = 1
        } else if path == "/contacts" {
            index = 2
        } else if path == "/wallet" || path == "/exchange" || path == "/cards" {
            index = 3
        } else if path == "/" || path.hasPrefix("/chat/") {
            index = 0
        } else {
            index = 4
        }
        guard let items = gcLiquidGlassTabBar?.items, items.indices.contains(index) else { return }
        gcLiquidGlassTabBar?.selectedItem = items[index]
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard tabBar === gcLiquidGlassTabBar, gcLiquidGlassRoutes.indices.contains(item.tag) else { return }
        let route = gcLiquidGlassRoutes[item.tag]
        let hash = route == "/" ? "#/" : "#\(route)"
        gcLiquidGlassBridgeController?.bridge?.webView?.evaluateJavaScript("window.location.hash = '\(hash)';")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.gcLiquidGlassHandler else { return }
        if let payload = message.body as? [String: Any] {
            let hash = payload["hash"] as? String ?? "#/"
            let visible = payload["visible"] as? Bool ?? false
            gcSetLiquidGlassTabBar(visible: visible, hash: hash)
            return
        }
        // Backward-compatible with a stale document that executed the previous one-string bridge.
        if let hash = message.body as? String {
            gcSetLiquidGlassTabBar(visible: true, hash: hash)
        }
    }

}
