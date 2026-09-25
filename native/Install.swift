#if os(macOS)
import Foundation
import Darwin

// A release bundle carries what make install would otherwise put in place:
// the source kit a config recompile builds against, and an engine compiled
// from the shipped config. They are installed once per bundle version.
struct BundledInstall {
    enum Outcome: Equatable { case current, installed, upgraded }

    let bundle: URL
    let support: URL
    let home: URL
    let stamp: String

    static var app: BundledInstall {
        let info=Bundle.main.infoDictionary ?? [:]
        let short=info["CFBundleShortVersionString"] as? String ?? "?"
        let build=info["CFBundleVersion"] as? String ?? "?"
        return BundledInstall(bundle:Bundle.main.bundleURL,
          support:FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/XMonadMac",isDirectory:true),
          home:FileManager.default.homeDirectoryForCurrentUser,
          stamp:"\(short) (\(build))")
    }

    var helpers: URL { bundle.appendingPathComponent("Contents/Helpers",isDirectory:true) }
    var bundledEngine: URL { helpers.appendingPathComponent("xmonad-engine") }
    var bundledKit: URL { bundle.appendingPathComponent("Contents/Resources/build-kit",isDirectory:true) }
    var engine: URL { support.appendingPathComponent("xmonad-engine") }
    var marker: URL { support.appendingPathComponent("bundle-version") }
    var hasPayload: Bool {
        let fm=FileManager.default
        return fm.isExecutableFile(atPath:bundledEngine.path)
          && fm.fileExists(atPath:bundledKit.appendingPathComponent("xmonad-macos.cabal").path)
    }

    // The CLI reads this to find a bundle that is not in ~/Applications.
    func recordAppPath() {
        try? (bundle.path+"\n").write(to:support.appendingPathComponent("app-path"),
                                      atomically:true,encoding:.utf8)
    }

    // An upgrade over an existing engine asks for a recompile: that engine was
    // built from the user's config against the previous kit.
    func run() throws -> Outcome {
        guard hasPayload else { return .current }
        let fm=FileManager.default
        if let installed=try? String(contentsOf:marker,encoding:.utf8),
           installed.trimmingCharacters(in:.whitespacesAndNewlines) == stamp,
           fm.isExecutableFile(atPath:engine.path) {
            return .current
        }
        try fm.createDirectory(at:support,withIntermediateDirectories:true,
                               attributes:[.posixPermissions:0o700])
        try installKit()
        try installLibraries()
        let hadEngine=fm.isExecutableFile(atPath:engine.path)
        if !hadEngine { try replace(engine,with:bundledEngine) }
        try installDefaultConfig()
        installCommands()
        try (stamp+"\n").write(to:marker,atomically:true,encoding:.utf8)
        return hadEngine ? .upgraded : .installed
    }

    // The previous kit's build cache is carried over, or the first recompile
    // after every upgrade rebuilds the whole library.
    private func installKit() throws {
        let fm=FileManager.default
        let current=support.appendingPathComponent("build-kit",isDirectory:true)
        let staged=support.appendingPathComponent("build-kit.new",isDirectory:true)
        let previous=support.appendingPathComponent("build-kit.previous",isDirectory:true)
        try? fm.removeItem(at:staged)
        try fm.copyItem(at:bundledKit,to:staged)
        let cache=current.appendingPathComponent("dist-newstyle",isDirectory:true)
        if fm.fileExists(atPath:cache.path) {
            try? fm.copyItem(at:cache,to:staged.appendingPathComponent("dist-newstyle"))
        }
        try? fm.removeItem(at:previous)
        if fm.fileExists(atPath:current.path) { try fm.moveItem(at:current,to:previous) }
        try fm.moveItem(at:staged,to:current)
    }
    // The bundled engine loads non-system libraries from beside itself.
    private func installLibraries() throws {
        let fm=FileManager.default
        for name in try fm.contentsOfDirectory(atPath:helpers.path) where name.hasSuffix(".dylib") {
            try replace(support.appendingPathComponent(name),with:helpers.appendingPathComponent(name))
        }
    }
    private func installDefaultConfig() throws {
        let fm=FileManager.default
        let legacy=home.appendingPathComponent(".xmonad/xmonad.hs")
        let config=home.appendingPathComponent(".config/xmonad-mac/xmonad.hs")
        guard !fm.fileExists(atPath:legacy.path),!fm.fileExists(atPath:config.path) else { return }
        try fm.createDirectory(at:config.deletingLastPathComponent(),withIntermediateDirectories:true,
                               attributes:[.posixPermissions:0o700])
        try fm.copyItem(at:bundledKit.appendingPathComponent("config/xmonad.hs"),to:config)
    }
    // Both command names are the engine itself. A file the user put there
    // instead of a link is left alone.
    private func installCommands() {
        let fm=FileManager.default
        let bin=home.appendingPathComponent(".local/bin",isDirectory:true)
        try? fm.createDirectory(at:bin,withIntermediateDirectories:true)
        for name in ["xmonad","xmonadctl"] {
            let link=bin.appendingPathComponent(name)
            if let attrs=try? fm.attributesOfItem(atPath:link.path) {
                guard attrs[.type] as? FileAttributeType == .typeSymbolicLink else { continue }
                try? fm.removeItem(at:link)
            }
            try? fm.createSymbolicLink(at:link,withDestinationURL:engine)
        }
    }
    // Rename over the target so a running engine keeps its old inode.
    private func replace(_ target: URL,with source: URL) throws {
        let fm=FileManager.default
        let staged=target.appendingPathExtension("new")
        try? fm.removeItem(at:staged)
        try fm.copyItem(at:source,to:staged)
        guard rename(staged.path,target.path) == 0 else {
            throw WireError.invalid("Cannot install \(target.path): errno \(errno)")
        }
    }
}
#endif
