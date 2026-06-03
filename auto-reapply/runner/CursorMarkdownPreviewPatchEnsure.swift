import Foundation

let bundle = Bundle.main
let env = ProcessInfo.processInfo.environment
let fileManager = FileManager.default

func infoValue(_ key: String) -> String? {
    bundle.object(forInfoDictionaryKey: key) as? String
}

func expandedHomePath(_ path: String) -> String {
    if path == "~" {
        return NSHomeDirectory()
    }
    if path.hasPrefix("~/") {
        return NSHomeDirectory() + String(path.dropFirst())
    }
    return path
}

let repoPath = expandedHomePath(
    env["CURSOR_MARKDOWN_PREVIEW_PATCH_REPO"]
        ?? infoValue("CursorMarkdownPreviewPatchRepo")
        ?? "\(NSHomeDirectory())/code/cursor-markdown-preview-patch"
)

let ensurePath = expandedHomePath(
    env["CURSOR_MARKDOWN_PREVIEW_PATCH_ENSURE"]
        ?? infoValue("CursorMarkdownPreviewPatchEnsure")
        ?? "\(repoPath)/ensure-patched"
)

let logDirectory = expandedHomePath(
    env["CURSOR_MARKDOWN_PREVIEW_PATCH_LOG_DIR"]
        ?? infoValue("CursorMarkdownPreviewPatchLogDir")
        ?? "\(NSHomeDirectory())/Library/Logs/cursor-markdown-preview-patch"
)

try? fileManager.createDirectory(
    atPath: logDirectory,
    withIntermediateDirectories: true
)

let logPath = "\(logDirectory)/ensure.log"
let errPath = "\(logDirectory)/ensure.err.log"

func appendLine(_ path: String, _ line: String) {
    let data = Data((line + "\n").utf8)
    if !fileManager.fileExists(atPath: path) {
        fileManager.createFile(atPath: path, contents: data)
        return
    }

    guard let handle = FileHandle(forWritingAtPath: path) else {
        return
    }
    defer {
        try? handle.close()
    }
    _ = try? handle.seekToEnd()
    _ = try? handle.write(contentsOf: data)
}

func appendHeader() {
    let formatter = ISO8601DateFormatter()
    appendLine(logPath, "=== Cursor Markdown preview patch ensure runner \(formatter.string(from: Date())) ===")
}

appendHeader()

guard fileManager.isExecutableFile(atPath: ensurePath) else {
    appendLine(errPath, "error: ensure-patched is not executable: \(ensurePath)")
    exit(1)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: ensurePath)
process.arguments = Array(CommandLine.arguments.dropFirst())
process.currentDirectoryURL = URL(fileURLWithPath: repoPath)

var childEnv = env
childEnv["CURSOR_MARKDOWN_PREVIEW_PATCH_LOG_DIR"] = logDirectory
process.environment = childEnv

let stdoutHandle = FileHandle(forWritingAtPath: logPath)
    ?? {
        fileManager.createFile(atPath: logPath, contents: nil)
        return FileHandle(forWritingAtPath: logPath)
    }()

let stderrHandle = FileHandle(forWritingAtPath: errPath)
    ?? {
        fileManager.createFile(atPath: errPath, contents: nil)
        return FileHandle(forWritingAtPath: errPath)
    }()

_ = try? stdoutHandle?.seekToEnd()
_ = try? stderrHandle?.seekToEnd()
process.standardOutput = stdoutHandle
process.standardError = stderrHandle

do {
    try process.run()
    process.waitUntilExit()
} catch {
    appendLine(errPath, "error: failed to run \(ensurePath): \(error)")
    exit(1)
}

let status = process.terminationStatus
appendLine(logPath, "runner exit status: \(status)")

try? stdoutHandle?.close()
try? stderrHandle?.close()

exit(status)
