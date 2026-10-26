// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation
import Darwin

enum HelperPaths {
    static let label = "com.yeonza.LidKeeper.helper"
    static let executable = "/Library/PrivilegedHelperTools/\(label)"
    static let plist = "/Library/LaunchDaemons/\(label).plist"
    static let state = "/Library/Application Support/LidKeeper"
    static let runtime = "/private/var/run/LidKeeper"
}

/// Descriptors, not user-controlled path strings, are used for IPC reads.
/// Only small regular files with a single link and the enrolled user's owner
/// are accepted. Root never follows symlinks or executes request contents.
enum SecureFiles {
    static func directory(_ path: String, owner: uid_t, privateMode: Bool = false) throws -> Int32 {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw HelperError.unsafeFile(path) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == owner,
              info.st_mode & (privateMode ? 0o077 : 0o022) == 0 else {
            close(fd)
            throw HelperError.unsafeFile(path)
        }
        return fd
    }

    static func ensureDirectory(_ path: String, owner: uid_t, mode: mode_t) throws {
        if mkdir(path, mode) != 0 && errno != EEXIST { throw HelperError.system("无法创建安全目录。") }
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw HelperError.unsafeFile(path) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == 0 || info.st_uid == owner,
              info.st_mode & 0o022 == 0 else { throw HelperError.unsafeFile(path) }
        guard fchown(fd, owner, owner == 0 ? 0 : gid_t.max) == 0, fchmod(fd, mode) == 0 else {
            throw HelperError.unsafeFile(path)
        }
    }

    static func read(directory: Int32, name: String, owner: uid_t,
                     limit: Int = 4096) throws -> (Data, Double)? {
        guard !name.contains("/"), name != ".", name != ".." else { throw HelperError.invalidRequest }
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 && errno == ENOENT { return nil }
        guard fd >= 0 else { throw HelperError.unsafeFile(name) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == owner,
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o022 == 0,
              info.st_nlink == 1, info.st_size >= 0, info.st_size <= limit else {
            throw HelperError.unsafeFile(name)
        }
        var bytes = [UInt8](repeating: 0, count: limit + 1)
        var length = 0
        while length < bytes.count {
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(fd, buffer.baseAddress!.advanced(by: length), buffer.count - length)
            }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw HelperError.unsafeFile(name) }
            if count == 0 { break }
            length += count
        }
        guard length <= limit else { throw HelperError.unsafeFile(name) }
        return (Data(bytes.prefix(length)), Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    static func atomicWrite(_ data: Data, directory: Int32, name: String, mode: mode_t, durable: Bool = true) throws {
        let temporary = ".\(name).\(UUID().uuidString)"
        let fd = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode)
        guard fd >= 0 else { throw HelperError.unsafeFile(name) }
        defer { close(fd); unlinkat(directory, temporary, 0) }
        var offset = 0
        try data.withUnsafeBytes { buffer in
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw HelperError.system("无法保存恢复记录。") }
                offset += count
            }
        }
        guard fchmod(fd, mode) == 0, !durable || fsync(fd) == 0,
              renameat(directory, temporary, directory, name) == 0 else {
            throw HelperError.system("无法提交恢复记录。")
        }
        // fsync the containing directory makes the rename durable across a reboot.
        if durable { _ = fsync(directory) }
    }
}

final class FileSessionStore: SessionStore {
    let fd: Int32
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() throws { fd = try SecureFiles.directory(HelperPaths.state, owner: 0) }
    deinit { close(fd) }

    func loadSession() throws -> OwnedSession? {
        guard let value = try SecureFiles.read(directory: fd, name: "session.json", owner: 0) else { return nil }
        return try decoder.decode(OwnedSession.self, from: value.0)
    }
    func saveSession(_ value: OwnedSession) throws {
        try SecureFiles.atomicWrite(encoder.encode(value), directory: fd, name: "session.json", mode: 0o600)
    }
    func clearSession() throws {
        guard unlinkat(fd, "session.json", 0) == 0 || errno == ENOENT else {
            throw HelperError.system("无法清除恢复记录。")
        }
        _ = fsync(fd)
    }
    func saveStatus(_ value: HelperStatus) throws {
        try SecureFiles.atomicWrite(encoder.encode(value), directory: fd, name: "status.json", mode: 0o644, durable: false)
    }
}

final class RootLock {
    let fd: Int32
    init(directory: Int32, name: String = "control.lock") throws {
        fd = openat(directory, name, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        var info = stat()
        guard fd >= 0, fstat(fd, &info) == 0, info.st_uid == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              info.st_mode & 0o077 == 0 else {
            if fd >= 0 { close(fd) }
            throw HelperError.unsafeFile(name)
        }
    }
    deinit { close(fd) }
    func acquire(nonblocking: Bool = false) throws {
        guard flock(fd, LOCK_EX | (nonblocking ? LOCK_NB : 0)) == 0 else { throw HelperError.busy }
    }
    func release() { _ = flock(fd, LOCK_UN) }
}
