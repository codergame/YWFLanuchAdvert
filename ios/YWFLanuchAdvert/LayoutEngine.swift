import UIKit
import WebKit

final class NodeBox {
    let node: LayoutNode
    let view: UIView
    let children: [NodeBox]

    init(node: LayoutNode, view: UIView, children: [NodeBox]) {
        self.node = node
        self.view = view
        self.children = children
    }
}

enum LayoutEngine {
    static func build(node: LayoutNode, assets: AssetLocator, webDelegate: WKNavigationDelegate?, webViewProvider: () -> WKWebView?) -> NodeBox {
        let view = makeView(node, assets: assets, webDelegate: webDelegate, webViewProvider: webViewProvider)
        let children = (node.children ?? []).map {
            build(node: $0, assets: assets, webDelegate: webDelegate, webViewProvider: webViewProvider)
        }
        for child in children {
            view.addSubview(child.view)
        }
        view.clipsToBounds = true
        return NodeBox(node: node, view: view, children: children)
    }

    static func layout(root: NodeBox, in bounds: CGRect, document: LayoutDocument, assets: AssetLocator) {
        let design = CGFloat(document.designWidth > 0 ? document.designWidth : 375)
        let scale = bounds.width / design
        let screen = CGRect(origin: .zero, size: bounds.size)
        root.view.frame = bounds
        applyChrome(root, scale: scale)
        layoutChildren(root, scale: scale, screen: screen, assets: assets)
    }

    private static func makeView(_ node: LayoutNode, assets: AssetLocator, webDelegate: WKNavigationDelegate?, webViewProvider: () -> WKWebView?) -> UIView {
        switch node.type {
        case "image":
            let imageView = UIImageView()
            imageView.image = assets.image(for: node.src)
            imageView.contentMode = imageContentMode(node.contentMode)
            imageView.clipsToBounds = true
            imageView.backgroundColor = LayoutColors.color(node.backgroundColor)
            imageView.isUserInteractionEnabled = node.click != nil
            return imageView
        case "button":
            let button = UIButton(type: .custom)
            button.setTitle(node.text, for: .normal)
            button.setTitleColor(LayoutColors.color(node.textColor), for: .normal)
            button.backgroundColor = LayoutColors.color(node.backgroundColor)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            return button
        case "html":
            let provided = webViewProvider()
            let webView: WKWebView
            if let provided, provided.superview == nil {
                webView = provided
            } else {
                webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            }
            webView.navigationDelegate = webDelegate
            webView.isOpaque = false
            webView.backgroundColor = LayoutColors.color(node.backgroundColor)
            webView.scrollView.backgroundColor = .clear
            if node.source?.type == "inline" {
                webView.loadHTMLString(wrap(html: node.source?.html ?? ""), baseURL: nil)
            } else if let path = node.source?.path, let url = assets.fileURL(zipOrRelative: path) {
                webView.loadFileURL(url, allowingReadAccessTo: assets.readAccessURL())
            }
            return webView
        default:
            let view = UIView()
            view.backgroundColor = LayoutColors.color(node.backgroundColor)
            return view
        }
    }

    private static func wrap(html: String) -> String {
        """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;padding:0;background:transparent;}</style></head><body>\(html)</body></html>
        """
    }

    private static func imageContentMode(_ mode: String?) -> UIView.ContentMode {
        switch mode {
        case "fit":
            return .scaleAspectFit
        case "fill":
            return .scaleToFill
        default:
            return .scaleAspectFill
        }
    }

    private static func applyChrome(_ box: NodeBox, scale: CGFloat) {
        if let button = box.view as? UIButton {
            let fontSize = max(1, CGFloat(box.node.fontSize ?? 16) * scale)
            button.titleLabel?.font = UIFont.systemFont(ofSize: fontSize)
            button.layer.cornerRadius = CGFloat(box.node.cornerRadius ?? 0) * scale
            button.clipsToBounds = true
            let padding = box.node.padding?.scaled(scale) ?? .zero
            button.contentEdgeInsets = padding
        } else if box.node.type != "button" {
            box.view.backgroundColor = LayoutColors.color(box.node.backgroundColor)
        }
        for child in box.children {
            applyChrome(child, scale: scale)
        }
    }

    private static func layoutChildren(_ box: NodeBox, scale: CGFloat, screen: CGRect, assets: AssetLocator) {
        guard box.node.type == "container" else { return }
        let padding = box.node.padding?.scaled(scale) ?? .zero
        let content = box.view.bounds.inset(by: padding)
        switch box.node.layout ?? "absolute" {
        case "linear":
            layoutLinear(box, content: content, scale: scale, screen: screen, assets: assets)
        case "dock":
            layoutDock(box, content: content, scale: scale, screen: screen, assets: assets)
        default:
            layoutAbsolute(box, content: content, scale: scale, screen: screen, assets: assets)
        }
        for child in box.children {
            layoutChildren(child, scale: scale, screen: screen, assets: assets)
        }
    }

    private static func layoutAbsolute(_ box: NodeBox, content: CGRect, scale: CGFloat, screen: CGRect, assets: AssetLocator) {
        for child in box.children {
            let margin = child.node.margin?.scaled(scale) ?? .zero
            let size = resolveSize(child.node, parent: content.size, scale: scale, screen: screen, assets: assets)
            let origin = CGPoint(
                x: content.minX + CGFloat(child.node.x ?? 0) * scale + margin.left,
                y: content.minY + CGFloat(child.node.y ?? 0) * scale + margin.top
            )
            child.view.frame = CGRect(origin: origin, size: size)
        }
    }

    private static func layoutLinear(_ box: NodeBox, content: CGRect, scale: CGFloat, screen: CGRect, assets: AssetLocator) {
        let vertical = (box.node.direction ?? "vertical") != "horizontal"
        let spacing = CGFloat(box.node.spacing ?? 0) * scale
        let children = box.children
        guard !children.isEmpty else { return }

        var sizes: [CGSize] = []
        var margins: [UIEdgeInsets] = []
        var weights: [CGFloat] = []
        for child in children {
            let margin = child.node.margin?.scaled(scale) ?? .zero
            margins.append(margin)
            let parent = CGSize(
                width: max(0, content.width - margin.left - margin.right),
                height: max(0, content.height - margin.top - margin.bottom)
            )
            var size = resolveSize(child.node, parent: parent, scale: scale, screen: screen, assets: assets)
            let weight = CGFloat(child.node.weight ?? 0)
            if weight > 0 {
                let mode = vertical ? child.node.size.heightMode : child.node.size.widthMode
                if mode == "match" {
                    if vertical { size.height = 0 } else { size.width = 0 }
                }
            }
            sizes.append(size)
            weights.append(weight)
        }

        let gapCount = CGFloat(children.count - 1)
        func main(_ size: CGSize) -> CGFloat { vertical ? size.height : size.width }
        let marginMain = margins.enumerated().reduce(CGFloat(0)) { partial, item in
            let margin = item.element
            return partial + (vertical ? margin.top + margin.bottom : margin.left + margin.right)
        }
        let baseMain = sizes.reduce(CGFloat(0)) { $0 + main($1) } + spacing * gapCount + marginMain
        let available = vertical ? content.height : content.width
        let extra = max(0, available - baseMain)
        let weightSum = weights.reduce(0, +)
        if weightSum > 0 && extra > 0 {
            for index in sizes.indices where weights[index] > 0 {
                let add = extra * weights[index] / weightSum
                if vertical {
                    sizes[index].height += add
                } else {
                    sizes[index].width += add
                }
            }
        }

        let gravity = box.node.gravity ?? "start"
        var between = spacing
        var used = sizes.reduce(CGFloat(0)) { $0 + main($1) } + marginMain
        if gravity == "spaceBetween", children.count > 1, weightSum == 0 {
            between = max(0, available - used) / gapCount
        }
        used += between * gapCount
        var cursor = CGFloat(0)
        if gravity == "center" {
            cursor = max(0, (available - used) / 2)
        } else if gravity == "end" {
            cursor = max(0, available - used)
        }

        for index in children.indices {
            let margin = margins[index]
            var size = sizes[index]
            let align = children[index].node.align ?? "start"
            if vertical {
                let crossSpace = max(0, content.width - margin.left - margin.right)
                var cross = size.width
                var crossPos = CGFloat(0)
                if align == "stretch" {
                    cross = crossSpace
                } else if align == "center" {
                    crossPos = max(0, (crossSpace - cross) / 2)
                } else if align == "end" {
                    crossPos = max(0, crossSpace - cross)
                }
                size.width = cross
                children[index].view.frame = CGRect(
                    x: content.minX + margin.left + crossPos,
                    y: content.minY + cursor + margin.top,
                    width: size.width,
                    height: size.height
                )
                cursor += margin.top + size.height + margin.bottom + between
            } else {
                let crossSpace = max(0, content.height - margin.top - margin.bottom)
                var cross = size.height
                var crossPos = CGFloat(0)
                if align == "stretch" {
                    cross = crossSpace
                } else if align == "center" {
                    crossPos = max(0, (crossSpace - cross) / 2)
                } else if align == "end" {
                    crossPos = max(0, crossSpace - cross)
                }
                size.height = cross
                children[index].view.frame = CGRect(
                    x: content.minX + cursor + margin.left,
                    y: content.minY + margin.top + crossPos,
                    width: size.width,
                    height: size.height
                )
                cursor += margin.left + size.width + margin.right + between
            }
        }
    }

    private static func layoutDock(_ box: NodeBox, content: CGRect, scale: CGFloat, screen: CGRect, assets: AssetLocator) {
        var remaining = content
        for child in box.children {
            let margin = child.node.margin?.scaled(scale) ?? .zero
            let avail = CGSize(
                width: max(0, remaining.width - margin.left - margin.right),
                height: max(0, remaining.height - margin.top - margin.bottom)
            )
            let size = resolveSize(child.node, parent: avail, scale: scale, screen: screen, assets: assets)
            let dock = child.node.dock ?? "top"
            switch dock {
            case "bottom":
                let height = min(size.height, avail.height)
                child.view.frame = CGRect(
                    x: remaining.minX + margin.left,
                    y: remaining.maxY - margin.bottom - height,
                    width: avail.width,
                    height: height
                )
                remaining.size.height = max(0, remaining.height - height - margin.top - margin.bottom)
            case "left":
                let width = min(size.width, avail.width)
                child.view.frame = CGRect(
                    x: remaining.minX + margin.left,
                    y: remaining.minY + margin.top,
                    width: width,
                    height: avail.height
                )
                let consumed = width + margin.left + margin.right
                remaining.origin.x += consumed
                remaining.size.width = max(0, remaining.width - consumed)
            case "right":
                let width = min(size.width, avail.width)
                child.view.frame = CGRect(
                    x: remaining.maxX - margin.right - width,
                    y: remaining.minY + margin.top,
                    width: width,
                    height: avail.height
                )
                remaining.size.width = max(0, remaining.width - width - margin.left - margin.right)
            case "fill":
                child.view.frame = CGRect(
                    x: remaining.minX + margin.left,
                    y: remaining.minY + margin.top,
                    width: avail.width,
                    height: avail.height
                )
                remaining.size = .zero
            default:
                let height = min(max(0, size.height), avail.height)
                child.view.frame = CGRect(
                    x: remaining.minX + margin.left,
                    y: remaining.minY + margin.top,
                    width: avail.width,
                    height: height
                )
                let consumed = height + margin.top + margin.bottom
                remaining.origin.y += consumed
                remaining.size.height = max(0, remaining.height - consumed)
            }
        }
    }

    private static func resolveSize(_ node: LayoutNode, parent: CGSize, scale: CGFloat, screen: CGRect, assets: AssetLocator) -> CGSize {
        let needsIntrinsic = node.size.widthMode == "wrap" || node.size.heightMode == "wrap"
        let intrinsic = needsIntrinsic
            ? intrinsicSize(node, proposed: parent, scale: scale, screen: screen, assets: assets)
            : CGSize.zero
        let width = axis(
            node.size.widthMode,
            value: node.size.width,
            parent: parent.width,
            screen: screen.width,
            scale: scale,
            intrinsic: intrinsic.width
        )
        let height = axis(
            node.size.heightMode,
            value: node.size.height,
            parent: parent.height,
            screen: screen.height,
            scale: scale,
            intrinsic: intrinsic.height
        )
        return CGSize(width: max(0, width), height: max(0, height))
    }

    private static func axis(_ mode: String, value: Double?, parent: CGFloat, screen: CGFloat, scale: CGFloat, intrinsic: CGFloat) -> CGFloat {
        switch mode {
        case "fixed":
            return CGFloat(value ?? 0) * scale
        case "percent":
            return parent * CGFloat(value ?? 0) / 100
        case "fullscreen":
            return screen
        case "wrap":
            return intrinsic
        default:
            return parent
        }
    }

    private static func intrinsicSize(_ node: LayoutNode, proposed: CGSize, scale: CGFloat, screen: CGRect, assets: AssetLocator) -> CGSize {
        switch node.type {
        case "image":
            return assets.image(for: node.src)?.size ?? .zero
        case "button":
            let font = UIFont.systemFont(ofSize: max(1, CGFloat(node.fontSize ?? 16) * scale))
            let text = node.text ?? ""
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 200),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: font],
                context: nil
            )
            return CGSize(width: ceil(bounds.width) + 24 * scale, height: ceil(bounds.height) + 16 * scale)
        case "container":
            return measureContainer(node, proposed: proposed, scale: scale, screen: screen, assets: assets)
        default:
            return .zero
        }
    }

    private static func measureContainer(_ node: LayoutNode, proposed: CGSize, scale: CGFloat, screen: CGRect, assets: AssetLocator) -> CGSize {
        let padding = node.padding?.scaled(scale) ?? .zero
        let inner = CGSize(
            width: max(0, proposed.width - padding.left - padding.right),
            height: max(0, proposed.height - padding.top - padding.bottom)
        )
        let children = node.children ?? []
        let layout = node.layout ?? "absolute"
        if layout == "linear" {
            let vertical = (node.direction ?? "vertical") != "horizontal"
            let spacing = CGFloat(node.spacing ?? 0) * scale
            var main = CGFloat(0)
            var cross = CGFloat(0)
            for (index, child) in children.enumerated() {
                let margin = child.margin?.scaled(scale) ?? .zero
                let avail = CGSize(
                    width: max(0, inner.width - margin.left - margin.right),
                    height: max(0, inner.height - margin.top - margin.bottom)
                )
                let size = resolveSize(child, parent: avail, scale: scale, screen: screen, assets: assets)
                if vertical {
                    main += margin.top + size.height + margin.bottom
                    cross = max(cross, margin.left + size.width + margin.right)
                } else {
                    main += margin.left + size.width + margin.right
                    cross = max(cross, margin.top + size.height + margin.bottom)
                }
                if index < children.count - 1 { main += spacing }
            }
            if vertical {
                return CGSize(width: cross + padding.left + padding.right, height: main + padding.top + padding.bottom)
            }
            return CGSize(width: main + padding.left + padding.right, height: cross + padding.top + padding.bottom)
        }
        var maxX = CGFloat(0)
        var maxY = CGFloat(0)
        for child in children {
            let margin = child.margin?.scaled(scale) ?? .zero
            let size = resolveSize(child, parent: inner, scale: scale, screen: screen, assets: assets)
            maxX = max(maxX, CGFloat(child.x ?? 0) * scale + margin.left + size.width + margin.right)
            maxY = max(maxY, CGFloat(child.y ?? 0) * scale + margin.top + size.height + margin.bottom)
        }
        return CGSize(width: maxX + padding.left + padding.right, height: maxY + padding.top + padding.bottom)
    }
}
