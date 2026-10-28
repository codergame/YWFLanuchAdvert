import UIKit
import WebKit

@objc(YWFLanuchAdvertDelegate)
public protocol YWFLanuchAdvertDelegate: AnyObject {
    @objc(ywfLanuchAdvertShouldJumpWhenTimeReachedZero:)
    optional func ywfLanuchAdvertShouldJumpWhenTimeReachedZero(_ advert: YWFLanuchAdvert) -> Bool

    /// 每个 HTML 节点都会调用一次。返回一个尚未加入视图层级的新实例；返回 nil 或未实现时由 SDK 自己创建。
    @objc(ywfLanuchAdvertCustomWebView:)
    optional func ywfLanuchAdvertCustomWebView(_ advert: YWFLanuchAdvert) -> WKWebView?
}

@objc(YWFLanuchAdvert)
public class YWFLanuchAdvert: NSObject {
    @objc public static let shared = YWFLanuchAdvert()
    @objc public weak var delegate: YWFLanuchAdvertDelegate?

    private let store = PackageStore()
    private var domain = ""
    private var appKey = "default"
    private var defaultFile: String?
    private var defaultBundle: Bundle = .main
    private var canvas: SplashCanvas?
    private var showing = false
    private var pendingCompletion: (() -> Void)?

    private override init() {
        super.init()
    }

    @objc(startWithDomain:)
    public func start(domain: String) {
        start(domain: domain, appKey: "default")
    }

    @objc(startWithDomain:appKey:)
    public func start(domain: String, appKey: String) {
        self.domain = Self.normalize(domain)
        self.appKey = appKey.isEmpty ? "default" : appKey
        store.sync(domain: self.domain, appKey: self.appKey)
    }

    @objc(setDefaultLayoutWithFileName:bundle:)
    public func setDefaultLayout(fileName: String, bundle: Bundle) {
        defaultFile = fileName
        defaultBundle = bundle
    }

    @objc(showOnWindow:completion:)
    public func show(on window: UIWindow, completion: (() -> Void)?) {
        let work = {
            self.showNow(on: window, completion: completion)
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func showNow(on window: UIWindow, completion: (() -> Void)?) {
        if showing {
            return
        }
        if let ready = store.bestReadyAd() {
            showing = true
            present(
                document: ready.ad.layout,
                assets: AssetLocator(root: ready.directory, bundle: defaultBundle),
                window: window,
                adId: ready.ad.id,
                completion: completion
            )
            store.report(adId: ready.ad.id, type: "impression")
            return
        }
        if let local = loadDefault() {
            showing = true
            present(
                document: local.document,
                assets: AssetLocator(root: nil, bundle: local.bundle),
                window: window,
                adId: nil,
                completion: completion
            )
            return
        }
        completion?()
    }

    private func present(document: LayoutDocument, assets: AssetLocator, window: UIWindow, adId: String?, completion: (() -> Void)?) {
        let canvas = SplashCanvas(document: document, assets: assets) { [weak self] in
            self?.customWebView()
        }
        canvas.frame = window.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pendingCompletion = completion
        canvas.onTimeZero = { [weak self] in
            self?.shouldJump() ?? true
        }
        canvas.onOpenLink = { [weak self] _ in
            if let adId = adId {
                self?.store.report(adId: adId, type: "click")
            }
        }
        canvas.onFinish = { [weak self] in
            self?.close()
        }
        self.canvas = canvas
        window.addSubview(canvas)
    }

    private func customWebView() -> WKWebView? {
        guard let delegate = delegate else { return nil }
        let selector = #selector(YWFLanuchAdvertDelegate.ywfLanuchAdvertCustomWebView(_:))
        guard let object = delegate as? NSObjectProtocol, object.responds(to: selector) else {
            return nil
        }
        return delegate.ywfLanuchAdvertCustomWebView?(self)
    }

    private func shouldJump() -> Bool {
        guard let delegate = delegate else { return true }
        let selector = #selector(YWFLanuchAdvertDelegate.ywfLanuchAdvertShouldJumpWhenTimeReachedZero(_:))
        guard let object = delegate as? NSObjectProtocol, object.responds(to: selector) else {
            return true
        }
        return delegate.ywfLanuchAdvertShouldJumpWhenTimeReachedZero?(self) ?? true
    }

    private func close() {
        canvas?.removeFromSuperview()
        canvas = nil
        showing = false
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?()
    }

    private func loadDefault() -> (document: LayoutDocument, bundle: Bundle)? {
        guard let fileName = defaultFile else { return nil }
        let ns = fileName as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        guard let url = defaultBundle.url(forResource: base, withExtension: ext.isEmpty ? "json" : ext),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(LayoutDocument.self, from: data) else {
            return nil
        }
        return (document, defaultBundle)
    }

    private static func normalize(_ domain: String) -> String {
        var text = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") {
            text.removeLast()
        }
        if !text.contains("://") {
            text = "https://" + text
        }
        return text
    }
}
