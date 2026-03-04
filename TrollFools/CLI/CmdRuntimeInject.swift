//
//  CmdRuntimeInject.swift
//  TrollTitan
//
//  Run as root (e.g. via Execute.rootSpawn) to perform runtime ROP inject.
//  Used by the app so task_for_pid succeeds.
//

import ArgumentParser
import Foundation

struct CmdRuntimeInject: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "runtime-inject",
        abstract: "Inject a dylib into a running process by name (must run as root)"
    )

    @Argument(help: "Process name (executable name, e.g. Safari, Settings).")
    var processName: String

    @Argument(help: "Full path to the signed dylib (e.g. /var/containers/Bundle/Application/xxx.dylib).")
    var dylibPath: String

    func run() throws {
        guard !processName.isEmpty, !dylibPath.isEmpty else {
            throw ArgumentParser.ValidationError("processName and dylibPath are required.")
        }
        guard FileManager.default.fileExists(atPath: dylibPath) else {
            throw ArgumentParser.ValidationError("Dylib does not exist: \(dylibPath)")
        }
        let ok = TrollTitanInjectDylibIntoProcess(processName, dylibPath)
        if !ok {
            throw ExitCode.failure
        }
    }
}
