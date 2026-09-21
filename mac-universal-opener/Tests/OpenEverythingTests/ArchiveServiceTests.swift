import Foundation
import XCTest
@testable import OpenEverything

final class ArchiveServiceTests: XCTestCase {
    private var workspace: URL!
    private let payload = Data("archive fixture\n".utf8)

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )
        try payload.write(to: workspace.appendingPathComponent("fixture.txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    func testRequiredFormatsListAndExtract() async throws {
        let archives = try makeRequiredArchives()
        for archive in archives {
            try await assertListsAndExtracts(archive)
        }
    }

    func test7ZCapability() async throws {
        let archive = workspace.appendingPathComponent("fixture.7z")
        guard let sevenZipTool = findTool(["7zz", "7z"]) else {
            reportCapability("7Z", supported: false, detail: "fixture tool unavailable")
            return
        }
        try run(sevenZipTool, ["a", "-bd", archive.path, source.path])

        do {
            try await assertListsAndExtracts(archive)
            reportCapability("7Z", supported: true)
        } catch {
            reportCapability("7Z", supported: false, detail: error.localizedDescription)
        }
    }

    func testRARCapability() async throws {
        let archive = workspace.appendingPathComponent("fixture.rar")
        try Data(base64Encoded: Self.rarFixture)!.write(to: archive)

        do {
            let entries = try await ArchiveService.list(archive)
            guard entries.contains(where: { $0.contains("file1.txt") }) else {
                throw FixtureError.missingExpectedEntry("sub/dir1/file1.txt")
            }
            let destination = workspace.appendingPathComponent("rar-out")
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
            try await ArchiveService.extract(archive, to: destination)
            let extracted = destination.appendingPathComponent("sub/dir1/file1.txt")
            guard FileManager.default.fileExists(atPath: extracted.path) else {
                throw FixtureError.missingExpectedEntry("sub/dir1/file1.txt")
            }
            reportCapability("RAR", supported: true)
        } catch {
            reportCapability("RAR", supported: false, detail: error.localizedDescription)
        }
    }

    func testUnsafeAbsoluteAndTraversalArchiveEntriesAreRejected() async throws {
        for (name, storedPath) in [
            ("absolute", "/tmp/escaped.txt"),
            ("traversal", "../escaped.txt")
        ] {
            let archive = workspace.appendingPathComponent("\(name).tar")
            try makeTarFixture(entryName: storedPath).write(to: archive)

            do {
                _ = try await ArchiveService.list(archive)
                XCTFail("Expected \(storedPath) to be rejected while listing")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("unsafe path"))
                XCTAssertTrue(error.localizedDescription.contains(storedPath))
            }

            let destination = workspace.appendingPathComponent("\(name)-out")
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
            do {
                try await ArchiveService.extract(archive, to: destination)
                XCTFail("Expected \(storedPath) to be rejected before extraction")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("unsafe path"))
            }
        }

        XCTAssertThrowsError(
            try ArchiveService.validate(["safe\\..\\..\\escaped.txt"])
        )
    }

    func testTarLinksOutsideDestinationAreRejectedBeforeExtraction() async throws {
        for (name, type, target) in [
            ("symlink", Character("2"), "../../escaped-symlink.txt"),
            ("hardlink", Character("1"), "../escaped-hardlink.txt")
        ] {
            let archive = workspace.appendingPathComponent("\(name).tar")
            let records = [
                TarRecord(name: "safe/link", type: type, target: target),
                TarRecord(name: "safe/link/payload.txt", payload: payload)
            ]
            try makeTarFixture(records: records).write(to: archive)
            try await assertRejectedWithoutOutsideWrite(
                archive,
                outsideName: "escaped-\(name).txt"
            )
        }
    }

    func testSafeTarLinkWithSpacesInNameExtracts() async throws {
        let archive = workspace.appendingPathComponent("safe-spaced-link.tar")
        let records = [
            TarRecord(name: "safe/target.txt", payload: payload),
            TarRecord(
                name: "safe/link with spaces.txt",
                type: "2",
                target: "target.txt"
            )
        ]
        try makeTarFixture(records: records).write(to: archive)

        let destination = workspace.appendingPathComponent("safe-spaced-link-out")
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        try await ArchiveService.extract(archive, to: destination)

        let link = destination.appendingPathComponent(
            "safe/link with spaces.txt"
        )
        XCTAssertEqual(try Data(contentsOf: link), payload)
    }

    func testTarEntryWithNewlineInNameRemainsOneSafeEntry() async throws {
        let archive = workspace.appendingPathComponent("safe-newline-name.tar")
        let storedPath = "safe/line\nbreak.txt"
        try makeTarFixture(entryName: storedPath).write(to: archive)

        let entries = try await ArchiveService.list(archive)

        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entries[0].contains("\n"))

        let destination = workspace.appendingPathComponent("safe-newline-name-out")
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        try await ArchiveService.extract(archive, to: destination)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent(storedPath).path
            )
        )
    }

    func testUnsafeTarLinkWithSpacesInNameIsRejectedBeforeExtraction() async throws {
        let archive = workspace.appendingPathComponent("unsafe-spaced-link.tar")
        let records = [
            TarRecord(
                name: "safe/link with spaces",
                type: "2",
                target: "../../escaped-spaced-link.txt"
            ),
            TarRecord(name: "safe/link with spaces/payload.txt", payload: payload)
        ]
        try makeTarFixture(records: records).write(to: archive)

        try await assertRejectedWithoutOutsideWrite(
            archive,
            outsideName: "escaped-spaced-link.txt"
        )
    }

    func testTarSymlinkInsideDestinationExtractsSuccessfully() async throws {
        let archive = workspace.appendingPathComponent("internal-symlink.tar")
        let records = [
            TarRecord(name: "safe/target.txt", payload: payload),
            TarRecord(name: "safe/link.txt", type: "2", target: "target.txt")
        ]
        try makeTarFixture(records: records).write(to: archive)

        try await assertLinkExtractsPayload(
            archive,
            linkPath: "safe/link.txt"
        )
    }

    func testTarHardLinkToArchiveEntryExtractsSuccessfully() async throws {
        let archive = workspace.appendingPathComponent("internal-hardlink.tar")
        let records = [
            TarRecord(name: "safe/target.txt", payload: payload),
            TarRecord(name: "safe/link.txt", type: "1", target: "safe/target.txt")
        ]
        try makeTarFixture(records: records).write(to: archive)

        try await assertLinkExtractsPayload(
            archive,
            linkPath: "safe/link.txt"
        )
    }

    func testUnsafeTarLinkWithNewlineInNameIsRejectedBeforeExtraction() async throws {
        let archive = workspace.appendingPathComponent("unsafe-newline-link.tar")
        let records = [
            TarRecord(
                name: "safe/link\nname",
                type: "2",
                target: "../../escaped-newline-link.txt"
            ),
            TarRecord(name: "safe/link\nname/payload.txt", payload: payload)
        ]
        try makeTarFixture(records: records).write(to: archive)

        try await assertRejectedWithoutOutsideWrite(
            archive,
            outsideName: "escaped-newline-link.txt"
        )
    }

    func testZipSymlinkOutsideDestinationIsRejectedBeforeExtraction() async throws {
        let link = workspace.appendingPathComponent("zip-link")
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: "../escaped-zip.txt"
        )
        let archive = workspace.appendingPathComponent("symlink.zip")
        try run(
            "/usr/bin/zip",
            ["-y", archive.path, link.lastPathComponent, source.lastPathComponent],
            currentDirectory: workspace
        )

        try await assertRejectedWithoutOutsideWrite(
            archive,
            outsideName: "escaped-zip.txt"
        )
    }

    func testZipSymlinkInsideDestinationExtractsSuccessfully() async throws {
        let fixtureDirectory = workspace.appendingPathComponent(
            "zip-safe",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: true
        )
        try payload.write(to: fixtureDirectory.appendingPathComponent("target.txt"))
        try FileManager.default.createSymbolicLink(
            atPath: fixtureDirectory.appendingPathComponent("link.txt").path,
            withDestinationPath: "target.txt"
        )

        let archive = workspace.appendingPathComponent("internal-symlink.zip")
        try run(
            "/usr/bin/zip",
            ["-yr", archive.path, fixtureDirectory.lastPathComponent],
            currentDirectory: workspace
        )

        try await assertLinkExtractsPayload(
            archive,
            linkPath: "zip-safe/link.txt"
        )
    }

    func testEncryptedAndUnsupportedArchivesProduceClearErrors() async throws {
        let encrypted = workspace.appendingPathComponent("encrypted.zip")
        try run(
            "/usr/bin/zip",
            ["-j", "-P", "fixture-password", encrypted.path, source.path]
        )
        let unsupported = workspace.appendingPathComponent("unsupported.rar")
        try Data("not an archive".utf8).write(to: unsupported)

        for archive in [encrypted, unsupported] {
            do {
                let destination = workspace.appendingPathComponent(
                    "failed-\(archive.lastPathComponent)",
                    isDirectory: true
                )
                try FileManager.default.createDirectory(
                    at: destination,
                    withIntermediateDirectories: true
                )
                try await ArchiveService.extract(archive, to: destination)
                XCTFail("Expected \(archive.lastPathComponent) to fail")
            } catch {
                assertClearArchiveError(error)
            }
        }
    }

    func testCommandRunnerLimitsLargeOutputAndErrorWithoutBlocking() {
        let outputMarker = "readable output tail"
        let errorMarker = "readable archive failure"
        let result = ArchiveService.run(
            executable: "/bin/sh",
            arguments: [
                "-c",
                """
                /bin/dd if=/dev/zero of=/dev/stderr bs=1048576 count=4 2>/dev/null
                /bin/dd if=/dev/zero of=/dev/stdout bs=1048576 count=4 2>/dev/null
                echo "\(outputMarker)"
                echo "\(errorMarker)" >/dev/stderr
                exit 7
                """
            ]
        )

        XCTAssertEqual(result.status, 7)
        XCTAssertLessThanOrEqual(
            result.output.utf8.count,
            ArchiveService.diagnosticCaptureLimit
        )
        XCTAssertLessThanOrEqual(
            result.error.utf8.count,
            ArchiveService.diagnosticCaptureLimit
        )
        XCTAssertTrue(result.output.contains(outputMarker))
        XCTAssertTrue(result.error.contains(errorMarker))
    }

    func testCommandRunnerStopsCommandThatDoesNotExit() {
        let start = Date()
        let result = ArchiveService.run(
            executable: "/bin/sleep",
            arguments: ["10"],
            timeout: 0.1
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertTrue(result.error.contains("took too long"))
        XCTAssertTrue(result.error.contains("was stopped"))
    }

    func testArchiveActionsReportReadableTimeoutErrors() async throws {
        let archive = workspace.appendingPathComponent("stalled.tar")
        try makeTarFixture(entryName: "fixture.txt").write(to: archive)
        let destination = workspace.appendingPathComponent("stalled-out")
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        await assertTimeoutError {
            _ = try await ArchiveService.list(
                archive,
                runner: self.timeoutRunner(for: "-tf")
            )
        }
        await assertTimeoutError {
            _ = try await ArchiveService.list(
                archive,
                runner: self.timeoutRunner(for: "-tvf")
            )
        }
        await assertTimeoutError {
            try await ArchiveService.extract(
                archive,
                to: destination,
                runner: self.timeoutRunner(for: "-xf")
            )
        }
    }

    func testSingleFileTimeoutPreservesExistingOutput() async throws {
        let archive = workspace.appendingPathComponent("stalled.gz")
        try Data("compressed fixture".utf8).write(to: archive)
        let destination = workspace.appendingPathComponent("single-out")
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        let output = destination.appendingPathComponent("stalled")
        let original = Data("original output".utf8)
        try original.write(to: output)
        let runner: ArchiveService.CommandRunner = {
            _, arguments, _, standardOutput in
            XCTAssertEqual(arguments.first, "-xOf")
            if let standardOutput {
                XCTAssertNotEqual(standardOutput, output)
                try? Data("partial output".utf8).write(to: standardOutput)
            }
            return self.timedOutResult
        }

        await assertTimeoutError {
            try await ArchiveService.extract(
                archive,
                to: destination,
                runner: runner
            )
        }
        XCTAssertEqual(try Data(contentsOf: output), original)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: destination.path),
            ["stalled"]
        )
    }

    func testSingleFileSuccessReplacesExistingOutputAndRemovesTemporaryFile() async throws {
        let archive = workspace.appendingPathComponent("updated.gz")
        try Data("compressed fixture".utf8).write(to: archive)
        let destination = workspace.appendingPathComponent("successful-single-out")
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        let output = destination.appendingPathComponent("updated")
        try Data("original output".utf8).write(to: output)
        let replacement = Data("replacement output".utf8)
        let runner: ArchiveService.CommandRunner = {
            executable, arguments, _, standardOutput in
            XCTAssertEqual(executable, "/usr/bin/tar")
            XCTAssertEqual(arguments, ["-xOf", archive.path])
            guard let standardOutput else {
                XCTFail("Expected decompression output path")
                return ArchiveService.CommandResult(
                    status: 1,
                    output: "",
                    error: "Missing output path",
                    timedOut: false
                )
            }
            XCTAssertNotEqual(standardOutput, output)
            XCTAssertEqual(standardOutput.deletingLastPathComponent(), destination)
            XCTAssertTrue(standardOutput.lastPathComponent.hasSuffix(".partial"))
            try? replacement.write(to: standardOutput)
            return ArchiveService.CommandResult(
                status: 0,
                output: "",
                error: "",
                timedOut: false
            )
        }

        try await ArchiveService.extract(
            archive,
            to: destination,
            runner: runner
        )

        XCTAssertEqual(try Data(contentsOf: output), replacement)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: destination.path),
            ["updated"]
        )
    }

    func testSingleFileFailurePreservesExistingOutput() async throws {
        let archive = workspace.appendingPathComponent("broken.gz")
        try Data("compressed fixture".utf8).write(to: archive)
        let destination = workspace.appendingPathComponent("failed-single-out")
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        let output = destination.appendingPathComponent("broken")
        let original = Data("original output".utf8)
        try original.write(to: output)
        let runner: ArchiveService.CommandRunner = {
            _, _, _, standardOutput in
            if let standardOutput {
                XCTAssertNotEqual(standardOutput, output)
                try? Data("partial output".utf8).write(to: standardOutput)
            }
            return ArchiveService.CommandResult(
                status: 1,
                output: "",
                error: "Decompression failed",
                timedOut: false
            )
        }

        do {
            try await ArchiveService.extract(
                archive,
                to: destination,
                runner: runner
            )
            XCTFail("Expected decompression to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Decompression failed"))
        }
        XCTAssertEqual(try Data(contentsOf: output), original)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: destination.path),
            ["broken"]
        )
    }

    private var source: URL {
        workspace.appendingPathComponent("fixture.txt")
    }

    private var timedOutResult: ArchiveService.CommandResult {
        ArchiveService.CommandResult(
            status: 15,
            output: "",
            error: "The archive tool took too long to finish and was stopped.",
            timedOut: true
        )
    }

    private func timeoutRunner(
        for timedOutArgument: String
    ) -> ArchiveService.CommandRunner {
        { _, arguments, _, _ in
            if arguments.first == timedOutArgument {
                return self.timedOutResult
            }
            if arguments.first == "-tf" {
                return ArchiveService.CommandResult(
                    status: 0,
                    output: "fixture.txt\n",
                    error: "",
                    timedOut: false
                )
            }
            if arguments.first == "-tvf" {
                return ArchiveService.CommandResult(
                    status: 0,
                    output: "-rw-r--r--  0 user staff 16 Jan 1 00:00 fixture.txt\n",
                    error: "",
                    timedOut: false
                )
            }
            XCTFail("Unexpected archive command: \(arguments)")
            return ArchiveService.CommandResult(
                status: 1,
                output: "",
                error: "Unexpected archive command",
                timedOut: false
            )
        }
    }

    private func assertTimeoutError(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected archive action to time out", file: file, line: line)
        } catch {
            let message = error.localizedDescription.lowercased()
            XCTAssertTrue(message.contains("took too long"), message, file: file, line: line)
            XCTAssertTrue(message.contains("was stopped"), message, file: file, line: line)
        }
    }

    private func makeRequiredArchives() throws -> [URL] {
        let tar = workspace.appendingPathComponent("fixture.tar")
        try run("/usr/bin/tar", ["-cf", tar.path, "-C", workspace.path, "fixture.txt"])

        let zip = workspace.appendingPathComponent("fixture.zip")
        try run("/usr/bin/zip", ["-j", zip.path, source.path])

        var archives = [zip, tar]
        for (extensionName, tool) in [
            ("gz", "/usr/bin/gzip"),
            ("bz2", "/usr/bin/bzip2")
        ] {
            let archive = workspace.appendingPathComponent("fixture.\(extensionName)")
            try run(tool, ["-c", source.path], standardOutput: archive)
            archives.append(archive)
        }

        let xz = workspace.appendingPathComponent("fixture.xz")
        try Data(base64Encoded: Self.xzFixture)!.write(to: xz)
        archives.append(xz)

        for (extensionName, tool) in [
            ("tgz", "/usr/bin/gzip"),
            ("tbz", "/usr/bin/bzip2"),
            ("tbz2", "/usr/bin/bzip2")
        ] {
            let archive = workspace.appendingPathComponent(
                "fixture.\(extensionName)"
            )
            try run(tool, ["-c", tar.path], standardOutput: archive)
            archives.append(archive)
        }

        let txz = workspace.appendingPathComponent("fixture.txz")
        try Data(base64Encoded: Self.txzFixture)!.write(to: txz)
        archives.append(txz)
        return archives
    }

    private func findTool(_ names: [String]) -> String? {
        for directory in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            for name in names {
                let path = "\(directory)/\(name)"
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }
        return nil
    }

    private func assertListsAndExtracts(_ archive: URL) async throws {
        let entries = try await ArchiveService.list(archive)
        guard !entries.isEmpty else {
            throw FixtureError.missingExpectedEntry("fixture.txt")
        }

        let destination = workspace.appendingPathComponent(
            "out-\(archive.lastPathComponent)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        try await ArchiveService.extract(archive, to: destination)
        let extracted = destination.appendingPathComponent("fixture.txt")
        guard FileManager.default.fileExists(atPath: extracted.path) else {
            throw FixtureError.missingExpectedEntry("fixture.txt")
        }
        guard try Data(contentsOf: extracted) == payload else {
            throw FixtureError.payloadMismatch
        }
    }

    private func reportCapability(
        _ format: String,
        supported: Bool,
        detail: String? = nil
    ) {
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        let status = supported ? "supported" : "unsupported"
        let suffix = detail.map { ": \($0.replacingOccurrences(of: "\n", with: " "))" } ?? ""
        print("ARCHIVE_CAPABILITY \(format)=\(status) on \(version)\(suffix)")
    }

    private func makeTarFixture(entryName: String) -> Data {
        makeTarFixture(records: [TarRecord(name: entryName, payload: payload)])
    }

    private func makeTarFixture(records: [TarRecord]) -> Data {
        var archive = Data()
        for record in records {
            archive.append(makeTarRecord(record))
        }
        archive.append(Data(repeating: 0, count: 1024))
        return archive
    }

    private func makeTarRecord(_ record: TarRecord) -> Data {
        var header = [UInt8](repeating: 0, count: 512)

        func write(_ value: String, at offset: Int, length: Int) {
            for (index, byte) in value.utf8.prefix(length).enumerated() {
                header[offset + index] = byte
            }
        }

        write(record.name, at: 0, length: 100)
        write("0000644\0", at: 100, length: 8)
        write("0000000\0", at: 108, length: 8)
        write("0000000\0", at: 116, length: 8)
        write(String(format: "%011o\0", record.payload.count), at: 124, length: 12)
        write("00000000000\0", at: 136, length: 12)
        for index in 148..<156 {
            header[index] = 0x20
        }
        header[156] = record.type.asciiValue!
        write(record.target, at: 157, length: 100)
        write("ustar\0", at: 257, length: 6)
        write("00", at: 263, length: 2)
        let checksum = header.reduce(0) { $0 + Int($1) }
        write(String(format: "%06o\0 ", checksum), at: 148, length: 8)

        var archive = Data(header)
        archive.append(record.payload)
        archive.append(
            Data(
                repeating: 0,
                count: (512 - record.payload.count % 512) % 512
            )
        )
        return archive
    }

    private func assertRejectedWithoutOutsideWrite(
        _ archive: URL,
        outsideName: String
    ) async throws {
        let destination = workspace.appendingPathComponent(
            "out-\(archive.lastPathComponent)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        let outside = workspace.appendingPathComponent(outsideName)

        do {
            try await ArchiveService.extract(archive, to: destination)
            XCTFail("Expected unsafe archive link to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("unsafe path"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: destination.path),
            []
        )
    }

    private func assertLinkExtractsPayload(
        _ archive: URL,
        linkPath: String
    ) async throws {
        let entries = try await ArchiveService.list(archive)
        XCTAssertTrue(entries.contains(where: { $0.contains(linkPath) }))

        let destination = workspace.appendingPathComponent(
            "out-\(archive.lastPathComponent)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        try await ArchiveService.extract(archive, to: destination)

        let extractedLink = destination.appendingPathComponent(linkPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedLink.path))
        XCTAssertEqual(try Data(contentsOf: extractedLink), payload)
    }

    private func run(
        _ executable: String,
        _ arguments: [String],
        standardOutput: URL? = nil,
        currentDirectory: URL? = nil
    ) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardError = errorPipe
        var outputHandle: FileHandle?
        if let standardOutput {
            FileManager.default.createFile(
                atPath: standardOutput.path,
                contents: nil
            )
            let handle = try FileHandle(forWritingTo: standardOutput)
            outputHandle = handle
            process.standardOutput = handle
        }
        try process.run()
        process.waitUntilExit()
        try outputHandle?.close()
        let error = String(
            decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        XCTAssertEqual(process.terminationStatus, 0, error)
        if process.terminationStatus != 0 {
            throw FixtureError.commandFailed(error)
        }
    }

    private func assertClearArchiveError(
        _ error: Error,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let message = error.localizedDescription.lowercased()
        XCTAssertTrue(message.contains("macos could not"), message, file: file, line: line)
        XCTAssertTrue(
            message.contains("encrypted") && message.contains("unsupported"),
            message,
            file: file,
            line: line
        )
    }

    private enum FixtureError: Error {
        case commandFailed(String)
        case missingExpectedEntry(String)
        case payloadMismatch
    }

    private struct TarRecord {
        let name: String
        let type: Character
        let target: String
        let payload: Data

        init(
            name: String,
            type: Character = "0",
            target: String = "",
            payload: Data = Data()
        ) {
            self.name = name
            self.type = type
            self.target = target
            self.payload = payload
        }
    }

    // Public-domain rarfile project fixture: rar3-subdirs.rar.
    private static let rarFixture =
        "UmFyIRoHAM+QcwAADQAAAAAAAADiw3QgkDcABgAAAAYAAAADx6QEyTao9FAdMBIApIEAAHN1YlxkaXIyXGZpbGUyLnR4dACwfLUwZmlsZTIK+lF0IJA/AAgAAAAIAAAAA30kt3FIqPRQHTAaAKSBAABzdWJcd2l0aCBzcGFjZVxsb25nIGZuLnR4dADwCEdMbG9uZyBmbgojwXQgklcABQAAAAUAAAADwYnsL+Co9FAdMDIApIEAAHN1YlzDvMi1xKnDtuG4i8OoXGZpbGUudHh0AALGAvw1KQEg9gse6FwAZmlsZQAudHh0ALByoRVmaWxlChRcdCCQNwAGAAAABgAAAAME9yniMKj0UB0wEgCkgQAAc3ViXGRpcjFcZmlsZTEudHh0APAChIVmaWxlMQrRdXTgkC0AAAAAAAAAAAADAAAAADao9FAUMAgA7UEAAHN1YlxkaXIyALB/JjP75XTgkDMAAAAAAAAAAAADAAAAAEio9FAUMA4A7UEAAHN1Ylx3aXRoIHNwYWNlAPDLG06903TgkC4AAAAAAAAAAAADAAAAACSo9FAUMAkA7UEAAHN1YlxlbXB0eQDwcNkb8Ed04JJDAAAAAAAAAAAAAwAAAADgqPRQFDAeAO1BAABzdWJcw7zItcSpw7bhuIvDqAACxgL8NSkBIPYLHugAsDR2F89rdOCQLQAAAAAAAAAAAAMAAAAAMKj0UBQwCADtQQAAc3ViXGRpcjEA8MVYh6xSdOCQKAAAAAAAAAAAAAMAAAAA1aj0UBQwAwDtQQAAc3ViALAO1STEPXsAQAcA"

    private static let xzFixture =
        "/Td6WFoAAATm1rRGAgAhARYAAAB0L+WjAQAPYXJjaGl2ZSBmaXh0dXJlCgBshe2+DtCi/gABKBDlC2xgH7bzfQEAAAAABFla"

    private static let txzFixture =
        "/Td6WFoAAATm1rRGAgAhARYAAAB0L+Wj4Cf/AGpdADMaS3gT6rUXEp6F6tJgPFwu2vAShK4kMQnc+Rl2JV0Q43CIMT64+U5ZkOr6x41I8eQBZehnONKpClmS9tymRX/PtZ54UA+fmjmj4Vup5V+jsSUN8lJ42/ZJ7joTN6gvoc+eCUC0d5Je3QAAAAAqfrs503ZM+gABhgGAUAAAI5I5t7HEZ/sCAAAAAARZWg=="
}