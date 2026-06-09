import SwiftUI

/// Meaningful file classification used to colour the visualizations (instead of an
/// arbitrary per-name hue) and to drive the legend. Colour encodes *what kind of data*
/// occupies the space — far more informative than random confetti.
enum FileCategory: String, CaseIterable, Identifiable {
    case folder, application, code, image, video, audio, archive, document, diskImage, cache, system, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .folder:      return "Dossiers"
        case .application: return "Applications"
        case .code:        return "Code & dev"
        case .image:       return "Images"
        case .video:       return "Vidéos"
        case .audio:       return "Audio"
        case .archive:     return "Archives"
        case .document:    return "Documents"
        case .diskImage:   return "Images disque"
        case .cache:       return "Caches & logs"
        case .system:      return "Système"
        case .other:       return "Autres"
        }
    }

    var symbol: String {
        switch self {
        case .folder:      return "folder.fill"
        case .application: return "app.fill"
        case .code:        return "chevron.left.forwardslash.chevron.right"
        case .image:       return "photo.fill"
        case .video:       return "film.fill"
        case .audio:       return "music.note"
        case .archive:     return "doc.zipper"
        case .document:    return "doc.text.fill"
        case .diskImage:   return "opticaldiscdrive.fill"
        case .cache:       return "shippingbox.fill"
        case .system:      return "gearshape.fill"
        case .other:       return "doc.fill"
        }
    }

    /// Base hue/saturation/brightness for a clean, distinguishable palette.
    private var hsb: (h: Double, s: Double, b: Double) {
        switch self {
        case .folder:      return (0.58, 0.10, 0.78)   // neutral slate
        case .application: return (0.60, 0.62, 0.90)   // blue
        case .code:        return (0.78, 0.45, 0.85)   // violet
        case .image:       return (0.10, 0.70, 0.95)   // amber
        case .video:       return (0.95, 0.62, 0.92)   // pink/red
        case .audio:       return (0.83, 0.55, 0.90)   // magenta
        case .archive:     return (0.40, 0.55, 0.80)   // green
        case .document:    return (0.55, 0.45, 0.92)   // cyan
        case .diskImage:   return (0.50, 0.50, 0.85)   // teal
        case .cache:       return (0.08, 0.18, 0.72)   // muted tan
        case .system:      return (0.0, 0.0, 0.62)     // grey
        case .other:       return (0.0, 0.0, 0.74)     // light grey
        }
    }

    /// Flat category colour (used for legend, bars, inspector icon).
    var color: Color {
        let c = hsb
        return Color(hue: c.h, saturation: c.s, brightness: c.b)
    }

    /// Colour for a treemap tile / sunburst arc, gently darkened with depth so nesting
    /// reads without losing the category identity.
    func color(depth: Int) -> Color {
        let c = hsb
        let b = max(0.42, c.b - Double(min(depth, 6)) * 0.05)
        return Color(hue: c.h, saturation: c.s, brightness: b)
    }

    /// Whether black or white text is more legible on this category's tile.
    func prefersDarkText(depth: Int) -> Bool {
        let c = hsb
        let b = max(0.42, c.b - Double(min(depth, 6)) * 0.05)
        // Rough perceived luminance from HSB; low-saturation bright colours read light.
        let luminance = b * (1.0 - 0.4 * c.s)
        return luminance > 0.6
    }

    // MARK: - Classification

    private static let codeExt: Set<String> = ["swift","c","h","cpp","hpp","m","mm","java","kt","js","ts","jsx","tsx","py","rb","go","rs","php","cs","sh","pl","lua","sql","json","xml","yaml","yml","toml","gradle","podspec","lock"]
    private static let imageExt: Set<String> = ["png","jpg","jpeg","gif","heic","heif","tiff","tif","bmp","webp","raw","cr2","nef","arw","psd","svg","ico"]
    private static let videoExt: Set<String> = ["mov","mp4","m4v","avi","mkv","webm","flv","wmv","mpg","mpeg","prores"]
    private static let audioExt: Set<String> = ["mp3","aac","m4a","wav","aiff","flac","alac","ogg","caf","mid"]
    private static let archiveExt: Set<String> = ["zip","tar","gz","tgz","bz2","xz","7z","rar","zst","jar","war","pkg","cpgz"]
    private static let docExt: Set<String> = ["pdf","doc","docx","xls","xlsx","ppt","pptx","pages","numbers","key","txt","rtf","md","csv","epub","odt"]
    private static let diskExt: Set<String> = ["dmg","iso","sparseimage","sparsebundle","img"]

    static func of(node: FileNode) -> FileCategory {
        if SystemPaths.isCritical(node.url) { return .system }
        if node.isBundle { return .application }
        if node.isDirectory {
            if isCacheName(node.name) { return .cache }
            return .folder
        }
        let ext = (node.name as NSString).pathExtension.lowercased()
        if ext.isEmpty { return .other }
        if codeExt.contains(ext)    { return .code }
        if imageExt.contains(ext)   { return .image }
        if videoExt.contains(ext)   { return .video }
        if audioExt.contains(ext)   { return .audio }
        if archiveExt.contains(ext) { return .archive }
        if docExt.contains(ext)     { return .document }
        if diskExt.contains(ext)    { return .diskImage }
        if ext == "log" { return .cache }
        return .other
    }

    private static func isCacheName(_ name: String) -> Bool {
        ["Caches","Cache","Logs","GPUCache","Code Cache","tmp",
         "node_modules","DerivedData",".gradle","Pods","target",".venv","__pycache__"]
            .contains(name)
    }
}
