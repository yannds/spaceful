import Foundation
import Combine
import CryptoKit

/// One reclaimable item proposed to the user.
struct Suggestion: Identifiable {
    let id = UUID()
    let node: FileNode
    var subtitle: String        // why it was flagged
    var url: URL { node.url }
    var size: Int64 { node.size }
}

/// A themed bucket of suggestions (e.g. "Caches", "Doublons").
struct SuggestionGroup: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let blurb: String
    let safety: Safety
    var items: [Suggestion]

    enum Safety { case safe, review, caution }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// Scans a subtree **independently of navigation** to surface reclaimable space:
/// caches, dev artifacts, large files, unused (old) files and duplicates. A single
/// recursive pass collects everything; only files above the duplicate threshold are
/// retained, so memory stays bounded even on a whole-disk scan.
@MainActor
final class Analyzer: ObservableObject {
    @Published private(set) var groups: [SuggestionGroup] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var scannedItems = 0

    private let config: AnalyzerConfig
    private let queue = DispatchQueue(label: "utilit.analyze", qos: .utility)
    private var cancelFlag = AtomicFlag()

    init(config: AnalyzerConfig = .default) {
        self.config = config
    }

    func cancel() {
        cancelFlag.set()
        isAnalyzing = false
    }

    /// Drop suggestions matching `shouldRemove` (e.g. after the user trashes an item).
    func removeItems(where shouldRemove: (Suggestion) -> Bool) {
        groups = groups.compactMap { group in
            var g = group
            g.items.removeAll(where: shouldRemove)
            return g.items.isEmpty ? nil : g
        }
    }

    /// Restore a previously-captured set of groups (used to undo a batch trash).
    func restore(groups: [SuggestionGroup]) {
        self.groups = groups
    }

    func analyze(url: URL) {
        cancelFlag.set()                 // stop any previous run
        let flag = AtomicFlag()
        cancelFlag = flag
        groups = []
        scannedItems = 0
        isAnalyzing = true

        queue.async { [weak self, config] in
            guard let self else { return }
            var collector = Collector()
            _ = self.walk(url, isDownloads: url.path.contains("/Downloads"),
                          flag: flag, config: config, into: &collector)
            if flag.isSet { return }
            let groups = self.buildGroups(from: collector, config: config)
            DispatchQueue.main.async {
                guard !flag.isSet else { return }
                self.groups = groups
                self.isAnalyzing = false
            }
        }
    }

    // MARK: - Single-pass walk

    /// Accumulates raw findings during the walk. `nonisolated` plain struct — only
    /// touched on the analyzer's serial queue.
    private struct Collector {
        var bigFiles: [Finding] = []        // files >= duplicateMinSize
        var caches: [Finding] = []
        var devArtifacts: [Finding] = []
        var count = 0
    }

    private struct Finding {
        let url: URL
        let size: Int64
        let modDate: Date?
        let isDirectory: Bool
        let isBundle: Bool
    }

    /// Returns the subtree allocated size; fills `collector` along the way.
    nonisolated private func walk(_ url: URL, isDownloads: Bool, flag: AtomicFlag,
                                  config: AnalyzerConfig, into collector: inout Collector) -> Int64 {
        if flag.isSet { return 0 }
        // Never descend into — or suggest — OS-owned subtrees. Deleting them can brick macOS.
        if SystemPaths.isCritical(url) { return 0 }
        guard let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
            .contentModificationDateKey
        ]) else { return 0 }

        if values.isSymbolicLink == true { return 0 }

        let isDir = values.isDirectory ?? false
        let isBundle = values.isPackage ?? false
        let modDate = values.contentModificationDate

        collector.count += 1
        if collector.count % 4000 == 0 {
            let n = collector.count
            DispatchQueue.main.async { [weak self] in
                guard let self, !flag.isSet else { return }
                self.scannedItems = n
            }
        }

        // Leaf: regular file or bundle.
        if !isDir || isBundle {
            let size = isBundle ? subtreeBytes(url, flag: flag)
                                : Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            if size >= config.duplicateMinSize {
                collector.bigFiles.append(Finding(url: url, size: size, modDate: modDate,
                                                   isDirectory: false, isBundle: isBundle))
            }
            return size
        }

        // Directory: recurse, summing children.
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [])) ?? []
        var total: Int64 = 0
        for child in entries {
            if flag.isSet { return total }
            total += walk(child, isDownloads: isDownloads, flag: flag, config: config, into: &collector)
        }

        let name = url.lastPathComponent
        if !SystemPaths.isProtected(url) {
            if config.cacheDirectoryNames.contains(name), total > config.minCacheSize {
                collector.caches.append(Finding(url: url, size: total, modDate: modDate, isDirectory: true, isBundle: false))
            }
            if config.devArtifactNames.contains(name), total > config.minDevJunkSize {
                collector.devArtifacts.append(Finding(url: url, size: total, modDate: modDate, isDirectory: true, isBundle: false))
            }
        }
        return total
    }

    /// Fast size of a bundle/package without retaining child nodes.
    nonisolated private func subtreeBytes(_ url: URL, flag: AtomicFlag) -> Int64 {
        var total: Int64 = 0
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey], options: []) else { return 0 }
        for case let item as URL in e {
            if flag.isSet { return total }
            let v = try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: - Group construction

    nonisolated private func buildGroups(from c: Collector, config: AnalyzerConfig) -> [SuggestionGroup] {
        var groups: [SuggestionGroup] = []

        if let g = cacheGroup(c.caches, config: config) { groups.append(g) }
        if let g = devGroup(c.devArtifacts, config: config) { groups.append(g) }
        if let g = largeGroup(c.bigFiles, config: config) { groups.append(g) }
        if let g = oldGroup(c.bigFiles, config: config) { groups.append(g) }
        if let g = duplicatesGroup(c.bigFiles, config: config) { groups.append(g) }

        return groups.sorted { $0.totalSize > $1.totalSize }
    }

    nonisolated private func node(for f: Finding) -> FileNode {
        FileNode(url: f.url, name: f.url.lastPathComponent.isEmpty ? f.url.path : f.url.lastPathComponent,
                 isDirectory: f.isDirectory, isSymlink: false, isBundle: f.isBundle,
                 modificationDate: f.modDate, ownSize: f.size, size: f.size,
                 fileCount: f.isDirectory ? 0 : 1, parent: nil, children: [])
    }

    /// Keep only the topmost match per branch (never a dir and its descendant).
    nonisolated private func topmost(_ findings: [Finding], subtitle: String) -> [Suggestion] {
        var items: [Suggestion] = []
        var claimed: [String] = []
        for f in findings.sorted(by: { $0.url.path.count < $1.url.path.count }) {
            if claimed.contains(where: { f.url.path.hasPrefix($0 + "/") }) { continue }
            claimed.append(f.url.path)
            items.append(Suggestion(node: node(for: f), subtitle: subtitle))
        }
        return items.sorted { $0.size > $1.size }
    }

    nonisolated private func cacheGroup(_ findings: [Finding], config: AnalyzerConfig) -> SuggestionGroup? {
        let items = topmost(findings, subtitle: "Cache régénéré automatiquement")
        guard !items.isEmpty else { return nil }
        return SuggestionGroup(title: "Caches & journaux", symbol: "shippingbox",
                               blurb: "Données temporaires recréées par les apps. Suppression sans danger.",
                               safety: .safe, items: items)
    }

    nonisolated private func devGroup(_ findings: [Finding], config: AnalyzerConfig) -> SuggestionGroup? {
        let items = topmost(findings, subtitle: "Dépendances/artefacts de développement")
        guard !items.isEmpty else { return nil }
        return SuggestionGroup(title: "Artefacts de développement", symbol: "hammer",
                               blurb: "node_modules, DerivedData, caches de build — régénérables par vos outils.",
                               safety: .review, items: items)
    }

    nonisolated private func largeGroup(_ files: [Finding], config: AnalyzerConfig) -> SuggestionGroup? {
        let items = files.filter { $0.size >= config.largeFileThreshold }
            .sorted { $0.size > $1.size }
            .prefix(config.maxItemsPerGroup)
            .map { Suggestion(node: node(for: $0), subtitle: "Fichier volumineux (\(Format.bytes($0.size)))") }
        guard !items.isEmpty else { return nil }
        return SuggestionGroup(title: "Fichiers volumineux", symbol: "scalemass",
                               blurb: "Les plus gros fichiers trouvés. À vérifier avant de supprimer.",
                               safety: .caution, items: Array(items))
    }

    nonisolated private func oldGroup(_ files: [Finding], config: AnalyzerConfig) -> SuggestionGroup? {
        let now = Date()
        let items = files.filter { f in
            guard f.size >= config.oldFileMinSize, let d = f.modDate else { return false }
            return now.timeIntervalSince(d) > config.oldFileAge
        }
        .sorted { $0.size > $1.size }
        .prefix(config.maxItemsPerGroup)
        .map { Suggestion(node: node(for: $0), subtitle: "Inutilisé depuis \(Format.relativeDate($0.modDate))") }
        guard !items.isEmpty else { return nil }
        return SuggestionGroup(title: "Fichiers anciens (inutilisés)", symbol: "clock.arrow.circlepath",
                               blurb: "Volumineux et non modifiés depuis longtemps.",
                               safety: .caution, items: Array(items))
    }

    /// Find files with **identical content regardless of name**. Three escalating tests
    /// keep it both correct and cheap: same byte size → same partial fingerprint (first
    /// chunk) → same full-content hash. Only the last confirms a true duplicate, so two
    /// different files that merely start alike are never falsely flagged.
    nonisolated private func duplicatesGroup(_ files: [Finding], config: AnalyzerConfig) -> SuggestionGroup? {
        var bySize: [Int64: [Finding]] = [:]
        for f in files where !f.isBundle && !SystemPaths.isProtected(f.url) {
            bySize[f.size, default: []].append(f)
        }

        var items: [Suggestion] = []
        for (_, sameSize) in bySize where sameSize.count > 1 {
            // 1) cheap partial fingerprint to weed out obvious non-matches
            var byPartial: [String: [Finding]] = [:]
            for f in sameSize {
                if let h = partialHash(f.url, bytes: config.fingerprintBytes) {
                    byPartial[h, default: []].append(f)
                }
            }
            // 2) confirm survivors with a full-content hash
            for (_, candidates) in byPartial where candidates.count > 1 {
                var byFull: [String: [Finding]] = [:]
                for f in candidates {
                    if let h = fullHash(f.url, flag: AtomicFlag()) {
                        byFull[h, default: []].append(f)
                    }
                }
                for (_, confirmed) in byFull where confirmed.count > 1 {
                    let sorted = confirmed.sorted { ($0.modDate ?? .distantPast) > ($1.modDate ?? .distantPast) }
                    let keep = sorted[0].url.lastPathComponent
                    for extra in sorted.dropFirst() {
                        let renamed = extra.url.lastPathComponent != keep
                        let why = renamed
                            ? "Contenu identique à « \(keep) » (nom différent)"
                            : "Copie identique de « \(keep) »"
                        items.append(Suggestion(node: node(for: extra), subtitle: why))
                    }
                }
            }
        }
        guard !items.isEmpty else { return nil }
        items.sort { $0.size > $1.size }
        return SuggestionGroup(title: "Doublons (contenu identique)", symbol: "doc.on.doc",
                               blurb: "Fichiers au contenu strictement identique, même sous des noms différents. On garde le plus récent.",
                               safety: .review, items: Array(items.prefix(config.maxDuplicates)))
    }

    nonisolated private func partialHash(_ url: URL, bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: bytes)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Streaming SHA-256 of the whole file, so two files match only on identical content.
    nonisolated private func fullHash(_ url: URL, flag: AtomicFlag) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 1 << 20   // 1 MB
        while true {
            if flag.isSet { return nil }
            guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
