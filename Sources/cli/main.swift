// atollctl — drive the Atoll island from scripts.
// Talks to the AF_UNIX socket the app listens on (~/.config/atoll/atoll.sock).
// (Shipped as "atollctl" inside Atoll.app/Contents/MacOS — "atoll" would
// collide case-insensitively with the Atoll binary.)
//
//   atollctl toggle | expand | collapse
//   atollctl select <tab>
//   atollctl flash <message>
//   atollctl status

import Foundation

let args = CommandLine.arguments.dropFirst().joined(separator: " ")
let usage = "usage: atollctl <toggle|expand|collapse|select <tab>|flash <msg>|status>"
guard !args.isEmpty else {
    print(usage)
    exit(2)
}

let path = NSHomeDirectory() + "/.config/atoll/atoll.sock"
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
    path.utf8CString.withUnsafeBufferPointer { src in
        let n = min(src.count - 1, ptr.count - 1)
        ptr.baseAddress!.copyMemory(from: src.baseAddress!, byteCount: n)
    }
}

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else {
    print("err: socket() failed")
    exit(1)
}
defer { close(fd) }

let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connected == 0 else {
    print("err: is Atoll running? (connect \(path) failed)")
    exit(1)
}

args.withCString { c in
    _ = write(fd, c, strlen(c))
}

var buf = [UInt8](repeating: 0, count: 4096)
let n = read(fd, &buf, buf.count - 1)
var failed = true
if n > 0, let out = String(bytes: buf[0..<n], encoding: .utf8) {
    print(out.trimmingCharacters(in: .whitespacesAndNewlines))
    failed = out.hasPrefix("err")
}
exit(failed ? 1 : 0)
