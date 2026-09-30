
import SwiftUI
import Foundation
import CryptoKit

// Resolve the State property-wrapper type instead of the SDK State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

struct ContentView: View {
    @AppStorage("account") private var account = ""
    @AppStorage("maxFiles") private var maxFiles = "8000"
    @AppStorage("destination") private var destination = "~/Desktop/Twitter_Downloads"
    @AppStorage("imagesOnly") private var imagesOnly = false
    @AppStorage("removeDuplicates") private var removeDuplicates = true

    @ViewState<Double> private var progress = 0.0
    @ViewState<Int> private var downloaded = 0
    @ViewState<String> private var log = "Ready.\n"
    @ViewState<Bool> private var running = false
    @ViewState<Process?> private var process = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("X Downloader").font(.title2).bold()
            Text("Download media from an X / Twitter account using your Chrome cookies.")
                .foregroundStyle(.secondary)

            Form {
                TextField("Account", text: $account)
                HStack {
                    Text("Maximum files")
                    TextField("", text: $maxFiles)
                        .frame(width: 90)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Images only", isOn: $imagesOnly)
                Toggle("Remove exact duplicates automatically", isOn: $removeDuplicates)
                HStack {
                    TextField("Destination", text: $destination)
                    Button("Choose…") { chooseFolder() }
                }
            }
            .disabled(running)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ProgressView(value: progress, total: 1.0)
                    Text("\(Int(progress * 100))%")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                Text(downloaded > 0 ? "\(downloaded) file(s) downloaded" : "Waiting to start…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(running ? "Downloading…" : "↓ Download") { start() }
                    .disabled(running || account.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Open folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSString(string: destination).expandingTildeInPath))
                }
            }

            Text("Activity").font(.headline)
            ScrollView {
                Text(log)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(.quaternary.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(width: 680, height: 590)
    }

    func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        if p.runModal() == .OK, let url = p.url { destination = url.path }
    }

    func start() {
        let accountClean = account.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard accountClean.range(of: "^[A-Za-z0-9_]{1,15}$", options: .regularExpression) != nil,
              let fileLimit = Int(maxFiles), fileLimit > 0 else {
            append("Enter a valid X username and a positive maximum number of files.")
            return
        }
        let shouldRemoveDuplicates = removeDuplicates
        running = true
        progress = 0
        downloaded = 0
        log = "Preparing download for @\(account)…\n"

        let dir = NSString(string: destination).expandingTildeInPath
        let finalDir = URL(fileURLWithPath: dir).appendingPathComponent(accountClean)
        let rawDir = finalDir.appendingPathComponent("_raw")
        do { try FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true) }
        catch { append("❌ \(error.localizedDescription)"); running = false; return }

        let config: [String: Any] = [
            "extractor": [
                "base-directory": rawDir.path,
                "twitter": [
                    "directory": [],
                    "retweets": false,
                    "replies": false,
                    "videos": !imagesOnly,
                    "pinned": true,
                    "unique": true,
                    "text-tweets": false,
                    "filename": "{tweet_id}_{num}.{extension}",
                    "postprocessors": [[
                        "name": "metadata", "event": "post", "mode": "json",
                        "filename": "{tweet_id}.json"
                    ]]
                ]
            ]
        ]
        let configURL = rawDir.appendingPathComponent("_config.json")
        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configURL, options: .atomic)
        } catch { append("❌ \(error.localizedDescription)"); running = false; return }

        guard let gallery = findExecutable("gallery-dl") else {
            append("❌ gallery-dl not found. Install it with: brew install gallery-dl")
            running = false
            return
        }

        append("Using: \(gallery)")
        append("Maximum: \(fileLimit) file(s)")
        append("Mode: \(imagesOnly ? "IMAGES ONLY" : "IMAGES + VIDEOS")")
        append("Duplicates: \(removeDuplicates ? "REMOVE EXACT COPIES" : "KEEP")")
        append("Cookies: CHROME (authenticated session)")
        append("")

        let pr = Process()
        process = pr
        pr.executableURL = URL(fileURLWithPath: gallery)
        pr.arguments = ["--config-ignore", "--config", configURL.path,
                        "--cookies-from-browser", "chrome", "--no-colors",
                        "--Print", "after:XDOWNLOADER_FILE:{tweet_id}_{num}.{extension}",
                        "--range", "1-\(fileLimit)", "https://x.com/\(accountClean)"]
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        pr.environment = environment

        let pipe = Pipe()
        pr.standardOutput = pipe
        pr.standardError = pipe

        do { try pr.run() }
        catch {
            append("❌ \(error.localizedDescription)")
            running = false
            process = nil
            return
        }

        // Drain complete UTF-8 lines before handling process completion.
        DispatchQueue.global(qos: .userInitiated).async {
            let reader = pipe.fileHandleForReading
            var pending = Data()
            while true {
                let data = reader.availableData
                if data.isEmpty { break }
                pending.append(data)
                while let newline = pending.firstIndex(of: 10) {
                    let line = String(decoding: pending[..<newline], as: UTF8.self)
                    pending.removeSubrange(...newline)
                    DispatchQueue.main.async { parseOutput(line, max: fileLimit) }
                }
            }
            if !pending.isEmpty {
                let line = String(decoding: pending, as: UTF8.self)
                DispatchQueue.main.async { parseOutput(line, max: fileLimit) }
            }
            pr.waitUntilExit()
            DispatchQueue.main.async {
                if pr.terminationStatus != 0 {
                    append("❌ gallery-dl stopped (code \(pr.terminationStatus)). Check the activity above. Partial files remain in _raw.")
                } else {
                    append("\n📝 Renaming files…")
                    renameFiles(rawDir: rawDir, finalDir: finalDir, maxFiles: fileLimit)
                    if shouldRemoveDuplicates {
                        append("\n🔎 Checking for exact duplicates…")
                        removeExactDuplicates(in: finalDir)
                    }
                    progress = 1.0
                    append("\n✅ Finished.")
                }
                running = false
                process = nil
            }
        }
    }

    func parseOutput(_ text: String, max: Int) {
        if text.hasPrefix("XDOWNLOADER_FILE:") {
            downloaded += 1
            progress = min(Double(downloaded) / Double(max), 0.99)
        } else {
            append(text.trimmingCharacters(in: .newlines))
        }
    }

    func findExecutable(_ name: String) -> String? {
        ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    func append(_ s: String) {
        guard !s.isEmpty else { return }
        log += s + (s.hasSuffix("\n") ? "" : "\n")
        if log.count > 30000 { log = String(log.suffix(30000)) }
    }

    func sanitize(_ text: String) -> String {
        if text.isEmpty { return "no_text" }
        var t = text.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "#", with: "").replacingOccurrences(of: "@", with: "")
        t = t.replacingOccurrences(of: #"[/\\:*?"<>|\r\n\t]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count > 180 { t = String(t.prefix(180)) }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return t.isEmpty ? "no_text" : t
    }

    func uniqueURL(_ folder: URL, _ stem: String, _ ext: String) -> URL {
        let fm = FileManager.default
        var u = folder.appendingPathComponent("\(stem).\(ext)")
        if !fm.fileExists(atPath: u.path) { return u }
        var n = 2
        while fm.fileExists(atPath: u.path) {
            u = folder.appendingPathComponent("\(stem) (\(n)).\(ext)")
            n += 1
        }
        return u
    }

    func renameFiles(rawDir: URL, finalDir: URL, maxFiles: Int) {
        let fm = FileManager.default
        try? fm.createDirectory(at: finalDir, withIntermediateDirectories: true)
        guard let files = try? fm.contentsOfDirectory(at: rawDir, includingPropertiesForKeys: nil) else { return }
        var total = 0
        var moved = 0
        let jsons = files.filter { $0.pathExtension.lowercased() == "json" && $0.lastPathComponent != "_config.json" }

        for jf in jsons {
            if total >= maxFiles { break }
            guard let data = try? Data(contentsOf: jf),
                  let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let tweetID = "\(meta["tweet_id"] ?? jf.deletingPathExtension().lastPathComponent)"
            let content = (meta["content"] as? String) ?? (meta["text"] as? String) ?? (meta["full_text"] as? String) ?? ""
            let stem = sanitize(content.isEmpty ? "tweet_\(tweetID)" : content)
            let media = files.filter { $0.lastPathComponent.hasPrefix(tweetID + "_") }
            for (i, src) in media.enumerated() {
                if total >= maxFiles { break }
                let base = media.count > 1 ? "\(stem) \(i+1)" : stem
                let dest = uniqueURL(finalDir, base, src.pathExtension.lowercased())
                do {
                    try fm.moveItem(at: src, to: dest)
                    moved += 1; total += 1
                    append("📷 \(dest.lastPathComponent)")
                } catch { append("⚠️ \(error.localizedDescription)") }
            }
        }
        append("✓ \(moved) files renamed.")
    }

    func hash(_ url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        guard stream.streamStatus != .error else { return nil }
        defer { stream.close() }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n < 0 { return nil }
            if n == 0 { break }
            hasher.update(data: Data(buffer[0..<n]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func removeExactDuplicates(in folder: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return }
        var seen: [String: URL] = [:]
        var duplicates = 0
        for url in files where !url.lastPathComponent.hasPrefix(".") && url.lastPathComponent != "_raw" {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard let digest = hash(url) else { continue }
            let key = "\(size)-\(digest)"
            if let original = seen[key] {
                do {
                    try fm.removeItem(at: url)
                    duplicates += 1
                    append("🗑 Duplicate: \(url.lastPathComponent) (same as \(original.lastPathComponent))")
                } catch { append("⚠️ \(error.localizedDescription)") }
            } else {
                seen[key] = url
            }
        }
        append("✓ \(duplicates) exact duplicate(s) removed.")
    }
}

@main
struct XDownloaderApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .windowResizability(.contentSize)
    }
}
