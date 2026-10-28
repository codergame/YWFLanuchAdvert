import UIKit
import WebKit

final class SplashCanvas: UIView, WKNavigationDelegate {
    let document: LayoutDocument
    var onFinish: (() -> Void)?
    var onTimeZero: (() -> Bool)?
    var onOpenLink: ((String) -> Void)?

    private let assets: AssetLocator
    private let root: NodeBox
    private let skipButton = UIButton(type: .custom)
    private var proxies: [ActionBox] = []
    private var remaining: Int
    private var asked = false
    private var ended = false
    private var started = false
    private var timer: Timer?

    init(document: LayoutDocument, assets: AssetLocator, webViewProvider: @escaping () -> WKWebView?) {
        self.document = document
        self.assets = assets
        self.remaining = document.duration
        self.root = LayoutEngine.build(
            node: document.root,
            assets: assets,
            webDelegate: nil,
            webViewProvider: webViewProvider
        )
        super.init(frame: .zero)
        backgroundColor = .black
        addSubview(root.view)
        addSubview(skipButton)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        skipButton.isHidden = !document.skip.showsButton
        wire(root)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        timer?.invalidate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !started else { return }
        started = true
        startClock()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        LayoutEngine.layout(root: root, in: bounds, document: document, assets: assets)
        placeSkip()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            onOpenLink?(url.absoluteString)
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private func wire(_ box: NodeBox) {
        if let webView = box.view as? WKWebView {
            webView.navigationDelegate = self
        }
        if let click = box.node.click {
            let action = ActionBox { [weak self] in
                self?.perform(click)
            }
            proxies.append(action)
            if let button = box.view as? UIButton {
                button.addTarget(action, action: #selector(ActionBox.fire), for: .touchUpInside)
            } else {
                let tap = UITapGestureRecognizer(target: action, action: #selector(ActionBox.fireGesture(_:)))
                tap.cancelsTouchesInView = false
                box.view.addGestureRecognizer(tap)
                box.view.isUserInteractionEnabled = true
            }
        }
        for child in box.children {
            wire(child)
        }
    }

    private func perform(_ click: ClickAction) {
        if click.type == "dismiss" {
            finish()
            return
        }
        guard click.type == "openUrl", let raw = click.url, let url = URL(string: raw) else { return }
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else { return }
        onOpenLink?(raw)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func startClock() {
        updateSkipTitle()
        if remaining < 0 { return }
        if remaining == 0 {
            askJump()
            return
        }
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func tick() {
        if remaining > 0 {
            remaining -= 1
            updateSkipTitle()
        }
        if remaining == 0 {
            timer?.invalidate()
            timer = nil
            askJump()
        }
    }

    private func askJump() {
        if asked { return }
        asked = true
        let allow = onTimeZero?() ?? true
        if allow {
            finish()
        }
    }

    @objc private func skipTapped() {
        finish()
    }

    private func finish() {
        if ended { return }
        ended = true
        timer?.invalidate()
        timer = nil
        onFinish?()
    }

    private func updateSkipTitle() {
        skipButton.setTitle("\(document.skip.text) \(remaining)", for: .normal)
    }

    private func placeSkip() {
        let design = CGFloat(document.designWidth > 0 ? document.designWidth : 375)
        let scale = bounds.width / design
        let skip = document.skip
        skipButton.isHidden = !skip.showsButton
        skipButton.setTitleColor(LayoutColors.color(skip.textColor), for: .normal)
        skipButton.backgroundColor = LayoutColors.color(skip.backgroundColor)
        skipButton.titleLabel?.font = UIFont.systemFont(ofSize: max(1, CGFloat(skip.fontSize) * scale))
        skipButton.layer.cornerRadius = CGFloat(skip.cornerRadius) * scale
        skipButton.clipsToBounds = true
        skipButton.contentEdgeInsets = UIEdgeInsets(
            top: CGFloat(skip.paddingV ?? 6) * scale,
            left: CGFloat(skip.paddingH ?? 12) * scale,
            bottom: CGFloat(skip.paddingV ?? 6) * scale,
            right: CGFloat(skip.paddingH ?? 12) * scale
        )
        skipButton.sizeToFit()
        var frame = skipButton.bounds
        let safe = safeAreaInsets
        let ox = CGFloat(skip.offsetX) * scale
        let oy = CGFloat(skip.offsetY) * scale
        switch skip.position {
        case "topLeft":
            frame.origin = CGPoint(x: safe.left + ox, y: safe.top + oy)
        case "bottomLeft":
            frame.origin = CGPoint(x: safe.left + ox, y: bounds.height - safe.bottom - oy - frame.height)
        case "bottomRight":
            frame.origin = CGPoint(x: bounds.width - safe.right - ox - frame.width, y: bounds.height - safe.bottom - oy - frame.height)
        default:
            frame.origin = CGPoint(x: bounds.width - safe.right - ox - frame.width, y: safe.top + oy)
        }
        skipButton.frame = frame
    }
}

final class ActionBox: NSObject {
    private let run: () -> Void

    init(_ run: @escaping () -> Void) {
        self.run = run
    }

    @objc func fire() {
        run()
    }

    @objc func fireGesture(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view else { return }
        let point = gesture.location(in: view)
        if let hit = view.hitTest(point, with: nil), hit !== view {
            return
        }
        run()
    }
}
