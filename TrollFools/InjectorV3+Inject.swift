//
//  InjectorV3+Inject.swift
//  TrollTitan
//
//  Runtime dylib injection (ROP + CoreTrust bypass). Replaces Mach-O in-place editing.
//

import CocoaLumberjackSwift
import Foundation

extension InjectorV3 {
    enum Strategy: String, CaseIterable {
        case lexicographic
        case fast
        case preorder
        case postorder

        var localizedDescription: String {
            switch self {
            case .lexicographic: NSLocalizedString("Lexicographic", comment: "")
            case .fast: NSLocalizedString("Fast", comment: "")
            case .preorder: NSLocalizedString("Pre-order", comment: "")
            case .postorder: NSLocalizedString("Post-order", comment: "")
            }
        }
    }

    // MARK: - Instance Methods

    /// Injects dylibs into the **running** target process via ROP (opainject) and CoreTrust bypass.
    /// Target app must be running; process name = main executable name.
    func inject(_ assetURLs: [URL], shouldPersist: Bool) throws {
        let preparedAssetURLs = try preprocessAssets(assetURLs)
        precondition(!preparedAssetURLs.isEmpty, "No asset to inject.")

        try injectBundles(preparedAssetURLs
            .filter { $0.pathExtension.lowercased() == "bundle" })

        try injectDylibsRuntime(preparedAssetURLs
            .filter { $0.pathExtension.lowercased() == "dylib" || $0.pathExtension.lowercased() == "framework" })

        if shouldPersist {
            try persist(preparedAssetURLs)
        }
    }

    // MARK: - Private Methods

    fileprivate func injectBundles(_ assetURLs: [URL]) throws {
        guard !assetURLs.isEmpty else { return }
        for assetURL in assetURLs {
            let targetURL = bundleURL.appendingPathComponent(assetURL.lastPathComponent)
            try cmdCopy(from: assetURL, to: targetURL, clone: true, overwrite: true)
            try cmdChangeOwnerToInstalld(targetURL, recursively: true)
        }
    }

    /// Runtime inject: copy dylib to Application folder, CoreTrust bypass, chmod, then ROP inject via root helper (like Titanium).
    fileprivate func injectDylibsRuntime(_ assetURLs: [URL]) throws {
        guard !assetURLs.isEmpty else { return }

        let processName = executableURL.lastPathComponent
        let appRoot = "/var/containers/Bundle/Application"

        for assetURL in assetURLs {
            let dylibURL: URL
            if assetURL.pathExtension.lowercased() == "framework" {
                guard let exec = try? locateExecutableInBundle(assetURL) else { continue }
                dylibURL = exec
            } else {
                dylibURL = assetURL
            }

            let tempName = "trolltitan_\(UUID().uuidString)_\(dylibURL.lastPathComponent)"
            let injectURL = URL(fileURLWithPath: "\(appRoot)/\(tempName)")

            try cmdCopy(from: dylibURL, to: injectURL, clone: false, overwrite: true)
            try cmdCoreTrustBypass(injectURL, teamID: teamID)
            try cmdChangeOwnerToInstalld(injectURL, recursively: false)
            try cmdChmod(injectURL, mode: 0o755)

            let ok: Bool
            if let cliURL = Self.runtimeInjectCLIURL(), FileManager.default.isExecutableFile(atPath: cliURL.path) {
                ok = try runRuntimeInjectViaRootHelper(cliURL: cliURL, processName: processName, dylibPath: injectURL.path)
            } else {
                ok = TrollTitanInjectDylibIntoProcess(processName, injectURL.path)
            }

            if !ok {
                DDLogError("Runtime inject failed for \(dylibURL.lastPathComponent) into \(processName)", ddlog: logger)
                throw Error.generic(NSLocalizedString("Runtime injection failed. Make sure the app is running and installed via TrollStore.", comment: ""))
            }
            DDLogInfo("Injected \(dylibURL.lastPathComponent) into \(processName)", ddlog: logger)
        }
    }

    /// Path to trollfoolscli (installed at /usr/local/bin by Theos when packaged).
    private static func runtimeInjectCLIURL() -> URL? {
        let path = "/usr/local/bin/trollfoolscli"
        if FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        if let url = Bundle.main.url(forResource: "trollfoolscli", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: url.path) { return url }
        return nil
    }

    /// Spawn trollfoolscli with root persona to run runtime-inject (task_for_pid works as root).
    private func runRuntimeInjectViaRootHelper(cliURL: URL, processName: String, dylibPath: String) throws -> Bool {
        let receipt = try Execute.rootSpawnWithOutputs(
            binary: cliURL.path,
            arguments: ["runtime-inject", processName, dylibPath],
            ddlog: logger
        )
        if case .exit(let code) = receipt.terminationReason, code == EXIT_SUCCESS {
            return true
        }
        DDLogWarn("runtime-inject helper exited: \(receipt.terminationReason)", ddlog: logger)
        return false
    }

    // MARK: - Load command name (used by Eject when removing legacy Mach-O load commands)

    func loadCommandNameOfAsset(_ assetURL: URL) throws -> String {
        var name = "@rpath/"
        if checkIsBundle(assetURL) {
            precondition(assetURL.pathExtension == "framework", "Invalid framework: \(assetURL.path)")
            let machO = try locateExecutableInBundle(assetURL)
            name += machO.pathComponents.suffix(2).joined(separator: "/")
            precondition(name.contains(".framework/"), "Invalid framework name: \(name)")
        } else {
            precondition(assetURL.pathExtension == "dylib", "Invalid dylib: \(assetURL.path)")
            name += assetURL.lastPathComponent
            precondition(name.hasSuffix(".dylib"), "Invalid dylib name: \(name)")
        }
        return name
    }
}
