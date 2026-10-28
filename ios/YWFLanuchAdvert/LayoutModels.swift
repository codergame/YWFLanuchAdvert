import UIKit

struct LayoutDocument: Codable {
    var schema: Int
    var designWidth: Double
    var designHeight: Double?
    var duration: Int
    var skip: SkipStyle
    var root: LayoutNode
}

struct SkipStyle: Codable {
    var enabled: Bool?
    var visible: Bool?
    var text: String

    var showsButton: Bool {
        if let visible = visible { return visible }
        return enabled ?? true
    }
    var position: String
    var offsetX: Double
    var offsetY: Double
    var textColor: String
    var backgroundColor: String
    var fontSize: Double
    var cornerRadius: Double
    var paddingH: Double?
    var paddingV: Double?
}

struct Insets: Codable {
    var top: Double?
    var left: Double?
    var bottom: Double?
    var right: Double?

    func scaled(_ scale: CGFloat) -> UIEdgeInsets {
        UIEdgeInsets(
            top: CGFloat(top ?? 0) * scale,
            left: CGFloat(left ?? 0) * scale,
            bottom: CGFloat(bottom ?? 0) * scale,
            right: CGFloat(right ?? 0) * scale
        )
    }
}

struct SizeSpec: Codable {
    var widthMode: String
    var heightMode: String
    var width: Double?
    var height: Double?
}

struct ClickAction: Codable {
    var type: String
    var url: String?
}

struct HtmlSource: Codable {
    var type: String
    var html: String?
    var path: String?
}

struct LayoutNode: Codable {
    var id: String
    var type: String
    var layout: String?
    var direction: String?
    var spacing: Double?
    var gravity: String?
    var size: SizeSpec
    var margin: Insets?
    var padding: Insets?
    var backgroundColor: String?
    var x: Double?
    var y: Double?
    var dock: String?
    var weight: Double?
    var align: String?
    var click: ClickAction?
    var src: String?
    var contentMode: String?
    var text: String?
    var textColor: String?
    var fontSize: Double?
    var cornerRadius: Double?
    var source: HtmlSource?
    var children: [LayoutNode]?
}

enum LayoutColors {
    static func color(_ hex: String?) -> UIColor {
        guard var text = hex?.trimmingCharacters(in: .whitespacesAndNewlines), text.hasPrefix("#") else {
            return .clear
        }
        text.removeFirst()
        var value: UInt64 = 0
        guard Scanner(string: text).scanHexInt64(&value) else { return .clear }
        if text.count == 6 {
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }
        if text.count == 8 {
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: CGFloat((value >> 24) & 0xFF) / 255
            )
        }
        return .clear
    }
}

final class AssetLocator {
    let root: URL?
    let bundle: Bundle

    init(root: URL?, bundle: Bundle) {
        self.root = root
        self.bundle = bundle
    }

    func image(for ref: String?) -> UIImage? {
        guard let url = fileURL(for: ref) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    func fileURL(for ref: String?) -> URL? {
        guard let ref = ref else { return nil }
        if ref.hasPrefix("zip://") {
            return fileInsideRoot(String(ref.dropFirst("zip://".count)))
        }
        if ref.hasPrefix("bundle://") {
            return fileInsideBundle(String(ref.dropFirst("bundle://".count)))
        }
        return nil
    }

    func fileURL(zipOrRelative path: String) -> URL? {
        if path.hasPrefix("zip://") || path.hasPrefix("bundle://") {
            return fileURL(for: path)
        }
        return fileInsideRoot(path) ?? fileInsideBundle(path)
    }

    func readAccessURL() -> URL {
        root ?? bundle.bundleURL
    }

    private func fileInsideRoot(_ relative: String) -> URL? {
        guard let root = root else { return nil }
        let clean = relative.replacingOccurrences(of: "\\", with: "/")
        if clean.isEmpty || clean.contains("..") || clean.hasPrefix("/") { return nil }
        let url = root.appendingPathComponent(clean)
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        if filePath != rootPath && !filePath.hasPrefix(rootPath + "/") { return nil }
        return url
    }

    private func fileInsideBundle(_ relative: String) -> URL? {
        let ns = relative as NSString
        let file = ns.lastPathComponent as NSString
        let ext = file.pathExtension
        let base = file.deletingPathExtension
        var dir = ns.deletingLastPathComponent
        if dir == "." { dir = "" }
        if dir.isEmpty {
            return bundle.url(forResource: base, withExtension: ext.isEmpty ? nil : ext)
        }
        return bundle.url(forResource: base, withExtension: ext.isEmpty ? nil : ext, subdirectory: dir)
    }
}
