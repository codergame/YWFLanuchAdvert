import UIKit
import WebKit
import YWFLanuchAdvert

final class ViewController: UIViewController, YWFLanuchAdvertDelegate {
    private let domainField = UITextField()
    private let allowSwitch = UISwitch()
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1)
        YWFLanuchAdvert.shared.delegate = self
        YWFLanuchAdvert.shared.setDefaultLayout(fileName: "default_splash.json", bundle: .main)
        YWFLanuchAdvert.shared.start(domain: "http://127.0.0.1:8080")

        domainField.text = "http://127.0.0.1:8080"
        domainField.borderStyle = .roundedRect
        domainField.autocapitalizationType = .none
        domainField.autocorrectionType = .no
        domainField.placeholder = "广告域名"

        allowSwitch.isOn = true
        let allowLabel = UILabel()
        allowLabel.text = "归零后允许跳转"
        allowLabel.textColor = .white

        let swiftButton = makeButton("Swift 展示", action: #selector(showFromSwift))
        let objcButton = makeButton("Objective-C 展示", action: #selector(showFromObjC))

        statusLabel.textColor = UIColor(white: 0.8, alpha: 1)
        statusLabel.numberOfLines = 0
        statusLabel.text = "没有就绪的网络广告时，会展示包内 default_splash.json。"

        let allowRow = UIStackView(arrangedSubviews: [allowLabel, allowSwitch])
        allowRow.axis = .horizontal
        allowRow.spacing = 12

        let stack = UIStackView(arrangedSubviews: [domainField, allowRow, swiftButton, objcButton, statusLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func ywfLanuchAdvertShouldJumpWhenTimeReachedZero(_ advert: YWFLanuchAdvert) -> Bool {
        allowSwitch.isOn
    }

    func ywfLanuchAdvertCustomWebView(_ advert: YWFLanuchAdvert) -> WKWebView? {
        WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    }

    @objc private func showFromSwift() {
        guard let window = view.window else { return }
        YWFLanuchAdvert.shared.delegate = self
        YWFLanuchAdvert.shared.start(domain: domainField.text ?? "")
        statusLabel.text = "Swift 正在展示"
        YWFLanuchAdvert.shared.show(on: window) { [weak self] in
            self?.statusLabel.text = "Swift 展示结束，已进入首页"
        }
    }

    @objc private func showFromObjC() {
        guard let window = view.window else { return }
        statusLabel.text = "Objective-C 正在展示"
        ObjCEntry.show(on: window, allowJump: allowSwitch.isOn) { [weak self] in
            self?.statusLabel.text = "Objective-C 展示结束，已进入首页"
        }
    }

    private func makeButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 17)
        button.backgroundColor = UIColor(red: 0.76, green: 0.25, blue: 0.05, alpha: 1)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
}
