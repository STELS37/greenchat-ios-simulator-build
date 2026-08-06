import UIKit
import Capacitor
import WebKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UITabBarDelegate, WKScriptMessageHandler {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        gcInstallPrivacyShield()
        gcInstallNativeLiquidGlassTabBar()
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


    // GC_IOS_NATIVE_LIQUID_GLASS_TAB_BAR
    private weak var gcNativeTabBar: UITabBar?
    private weak var gcNativeBridgeController: CAPBridgeViewController?
    private var gcNativeTabBarInstallAttempts = 0
    private var gcNativeTabBarVisible = false
    private var gcNativeTabLanguage = ""
    private let gcNativeTabRoutes = ["/", "/calls", "/contacts", "/wallet", "/settings"]
    private static let gcNativeTabHandler = "gcNativeTabBar"

    private func gcInstallNativeLiquidGlassTabBar() {
        guard gcNativeTabBar == nil else { return }
        DispatchQueue.main.async { [weak self] in self?.gcTryInstallNativeLiquidGlassTabBar() }
    }

    private func gcTryInstallNativeLiquidGlassTabBar() {
        guard gcNativeTabBar == nil else { return }
        guard let window = self.window,
              let root = window.rootViewController,
              let bridgeController = gcFindBridgeController(root),
              let webView = bridgeController.bridge?.webView else {
            gcNativeTabBarInstallAttempts += 1
            if gcNativeTabBarInstallAttempts < 80 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.gcTryInstallNativeLiquidGlassTabBar()
                }
            }
            return
        }

        // The web document paints continuously behind the floating system bar. These settings remove
        // WKWebView's default white backing and prevent any synthetic bottom inset/strip.
        bridgeController.extendedLayoutIncludesOpaqueBars = true
        bridgeController.view.backgroundColor = UIColor.clear
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        let tabBar = UITabBar(frame: .zero)
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.delegate = self
        tabBar.tintColor = UIColor.systemGreen
        tabBar.unselectedItemTintColor = UIColor.secondaryLabel
        tabBar.itemPositioning = .automatic
        tabBar.isTranslucent = true
        tabBar.layer.zPosition = 1000
        tabBar.accessibilityIdentifier = "gc-native-liquid-glass-tab-bar"
        gcApplyNativeTabTitles(tabBar, language: Locale.preferredLanguages.first ?? "en")
        tabBar.selectedItem = tabBar.items?.first
        tabBar.alpha = 0
        tabBar.transform = CGAffineTransform(translationX: 0, y: 88)
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
        gcNativeBridgeController = bridgeController
        gcNativeTabBar = tabBar

        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: Self.gcNativeTabHandler)
        controller.add(self, name: Self.gcNativeTabHandler)
        let bootstrap = """
        (() => {
          let pending = false;
          let lastSignature = '';
          const publishNow = () => {
            pending = false;
            const shell = document.querySelector('.gc-superapp');
            const isPainted = (node) => {
              if (!(node instanceof Element) || node.hasAttribute('hidden')) return false;
              const style = window.getComputedStyle(node);
              if (style.display === 'none' || style.visibility === 'hidden' || style.visibility === 'collapse') return false;
              if (Number.parseFloat(style.opacity || '1') <= 0.01) return false;
              const rect = node.getBoundingClientRect();
              return rect.width > 1 && rect.height > 1;
            };
            const blockers = document.querySelectorAll(
              '.gc-overlay, .gc-palette-overlay, .gc-msgmenu-layer, .gc-sheet-layer, .gc-viewer, [aria-modal="true"]'
            );
            const blocked = Array.from(blockers).some(isPainted);
            // Android/APK hides the canonical rail whenever the shell enters gc-superapp-detail.
            // Native iOS mirrors that exact shell state instead of inventing a second route table.
            const visible = Boolean(shell && !shell.classList.contains('gc-superapp-detail') && !blocked);
            const root = document.documentElement;
            if (root) {
              if (visible) root.setAttribute('data-gc-native-tabbar', 'ios-native');
              else root.removeAttribute('data-gc-native-tabbar');
            }
            const hash = window.location.hash || '#/';
            const language = root?.lang || navigator.language || 'en';
            const signature = (visible ? '1' : '0') + '|' + hash + '|' + language;
            if (signature === lastSignature) return;
            lastSignature = signature;
            window.webkit?.messageHandlers?.gcNativeTabBar?.postMessage({ hash, visible, language });
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
          window.__gcNativeTabBarObserver.observe(document.documentElement, {
            attributes: true,
            attributeFilter: ['lang', 'class', 'hidden', 'aria-hidden'],
            childList: true,
            subtree: true
          });
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

    private func gcApplyNativeTabTitles(_ tabBar: UITabBar, language: String) {
        let russian = language.lowercased().hasPrefix("ru")
        let languageKey = russian ? "ru" : "en"
        let titles = russian
            ? ["Чаты", "Звонки", "Контакты", "Кошелёк", "Ещё"]
            : ["Chats", "Calls", "Contacts", "Wallet", "More"]
        if gcNativeTabLanguage == languageKey && tabBar.items?.count == titles.count { return }
        gcNativeTabLanguage = languageKey
        let symbols = ["message.fill", "phone.fill", "person.2.fill", "creditcard.fill", "ellipsis"]
        let selectedTag = tabBar.selectedItem?.tag ?? 0
        tabBar.items = titles.indices.map { index in
            UITabBarItem(title: titles[index], image: UIImage(systemName: symbols[index]), tag: index)
        }
        tabBar.selectedItem = tabBar.items?.first(where: { $0.tag == selectedTag }) ?? tabBar.items?.first
    }

    private func gcSetNativeTabBar(visible: Bool, hash: String, language: String) {
        guard let tabBar = gcNativeTabBar else { return }
        gcApplyNativeTabTitles(tabBar, language: language)
        if visible {
            gcSelectNativeTab(for: hash)
            gcNativeBridgeController?.view.bringSubviewToFront(tabBar)
        }

        let changed = gcNativeTabBarVisible != visible
        gcNativeTabBarVisible = visible
        tabBar.isUserInteractionEnabled = visible
        tabBar.accessibilityElementsHidden = !visible
        guard changed else { return }

        let hiddenTransform = CGAffineTransform(translationX: 0, y: max(tabBar.bounds.height, 72))
        if UIAccessibility.isReduceMotionEnabled {
            tabBar.layer.removeAllAnimations()
            tabBar.transform = visible ? .identity : hiddenTransform
            tabBar.alpha = visible ? 1 : 0
            tabBar.isHidden = !visible
            return
        }

        if visible {
            tabBar.isHidden = false
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                usingSpringWithDamping: 0.90,
                initialSpringVelocity: 0.12,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                animations: {
                    tabBar.transform = .identity
                    tabBar.alpha = 1
                }
            )
        } else {
            UIView.animate(
                withDuration: 0.20,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseIn],
                animations: {
                    tabBar.transform = hiddenTransform
                    tabBar.alpha = 0
                },
                completion: { [weak self] _ in
                    guard let self, !self.gcNativeTabBarVisible else { return }
                    self.gcNativeTabBar?.isHidden = true
                }
            )
        }
    }

    private func gcSelectNativeTab(for hash: String) {
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
        guard let items = gcNativeTabBar?.items, items.indices.contains(index) else { return }
        gcNativeTabBar?.selectedItem = items[index]
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard tabBar === gcNativeTabBar, gcNativeTabRoutes.indices.contains(item.tag) else { return }
        let route = gcNativeTabRoutes[item.tag]
        let hash = route == "/" ? "#/" : "#\(route)"
        gcNativeBridgeController?.bridge?.webView?.evaluateJavaScript("window.location.hash = '\(hash)';")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.gcNativeTabHandler else { return }
        guard let payload = message.body as? [String: Any] else { return }
        gcSetNativeTabBar(
            visible: payload["visible"] as? Bool ?? false,
            hash: payload["hash"] as? String ?? "#/",
            language: payload["language"] as? String ?? "en"
        )
    }

}
