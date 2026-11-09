import Foundation

struct BuildError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Runs `make-dmg.sh` and streams its output back line by line.
///
/// All of the disk-image work lives in that script: it is the same engine the
/// command line uses, so what the app produces and what `scripts/make-dmg.sh`
/// produces cannot drift apart.
final class DMGBuilder {

    private var process: Process?
    private var cancelled = false

    // MARK: - Locating the engine

    static func scriptURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "make-dmg", withExtension: "sh") {
            return bundled
        }
        // Running from a checkout (`swift run`): walk up from the executable
        // and look for the script in the repository.
        var directory = Bundle.main.bundleURL
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("scripts/make-dmg.sh")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory = directory.deletingLastPathComponent()
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/make-dmg.sh")
        return FileManager.default.fileExists(atPath: cwd.path) ? cwd : nil
    }

    // MARK: - Arguments

    /// Turns the document into an argument list for `make-dmg.sh`.
    static func arguments(for data: ProjectData) -> [String] {
        var args: [String] = []

        args += ["--volname", data.volumeName.trimmingCharacters(in: .whitespacesAndNewlines)]
        args += ["--output", data.outputPath]
        args += ["--window", "\(data.windowX),\(data.windowY)"]
        args += ["--window-size", "\(data.windowWidth),\(data.windowHeight)"]
        args += ["--icon-size", "\(data.iconSize)"]
        args += ["--text-size", "\(data.textSize)"]
        args += ["--format", data.format.rawValue]

        if !data.backgroundPath.isEmpty {
            args += ["--background", data.backgroundPath]
            if !data.background2xPath.isEmpty {
                args += ["--background-2x", data.background2xPath]
            }
        }
        if !data.volumeIconPath.isEmpty {
            args += ["--volume-icon", data.volumeIconPath]
        }

        for item in data.items where !item.isApplicationsLink {
            args += ["--add", item.sourcePath]
        }
        if data.hasApplicationsLink {
            args += ["--applications-link"]
        }
        for item in data.items {
            let x = Int(item.position.x.rounded())
            let y = Int(item.position.y.rounded())
            args += ["--pos", "\(item.displayName):\(x),\(y)"]
        }

        let identity = data.codesignIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        if !identity.isEmpty {
            args += ["--codesign", identity]
        }

        return args
    }

    /// The equivalent command line, for the "Copy command" button.
    static func shellCommand(for data: ProjectData) -> String {
        let script = scriptURL()?.path ?? "scripts/make-dmg.sh"
        let parts = [script] + arguments(for: data)
        return parts.map { part -> String in
            let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./=:,@+"))
            if part.unicodeScalars.allSatisfy({ safe.contains($0) }) { return part }
            return "'" + part.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
    }

    // MARK: - Running

    func build(data: ProjectData,
               onOutput: @escaping (String) -> Void,
               completion: @escaping (Result<URL, Error>) -> Void) {

        guard let script = DMGBuilder.scriptURL() else {
            completion(.failure(BuildError(message:
                "The build engine (make-dmg.sh) is missing from the app bundle.")))
            return
        }

        let arguments = DMGBuilder.arguments(for: data)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        self.process = process

        let emit: (String) -> Void = { line in
            DispatchQueue.main.async { onOutput(line) }
        }
        let finish: (Result<URL, Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }

        emit("$ " + DMGBuilder.shellCommand(for: data))
        emit("")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try process.run()
            } catch {
                finish(.failure(BuildError(message:
                    "The build engine could not be started: \(error.localizedDescription)")))
                return
            }

            var collected: [String] = []
            var buffer = Data()
            let handle = pipe.fileHandleForReading

            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<newline)
                    buffer.removeSubrange(buffer.startIndex...newline)
                    let line = String(data: lineData, encoding: .utf8) ?? ""
                    collected.append(line)
                    emit(line)
                }
            }
            if !buffer.isEmpty, let tail = String(data: buffer, encoding: .utf8), !tail.isEmpty {
                collected.append(tail)
                emit(tail)
            }

            process.waitUntilExit()
            let status = process.terminationStatus

            if self?.cancelled == true {
                finish(.failure(BuildError(message: "The build was cancelled.")))
                return
            }

            guard status == 0 else {
                let errors = collected.filter { $0.hasPrefix("ERROR:") }
                let detail = errors.isEmpty
                    ? (collected.suffix(6).joined(separator: "\n"))
                    : errors.joined(separator: "\n")
                finish(.failure(BuildError(message:
                    "The build failed (exit code \(status)).\n\n\(detail)")))
                return
            }

            let producedPath = collected
                .last(where: { $0.hasPrefix("DMG_PATH=") })
                .map { String($0.dropFirst("DMG_PATH=".count)) }
            let url = URL(fileURLWithPath: producedPath ?? data.outputPath)
            finish(.success(url))
        }
    }

    func cancel() {
        cancelled = true
        process?.terminate()
    }
}
