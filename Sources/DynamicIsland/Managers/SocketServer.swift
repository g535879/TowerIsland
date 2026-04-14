import Foundation
import DIShared

final class SocketServer: @unchecked Sendable {
    private let sessionManager: SessionManager
    private var serverFD: Int32 = -1
    private let queue = DispatchQueue(label: "dev.towerisland.socket", qos: .userInitiated)
    private var isRunning = false

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    func start() {
        let dir = DISocketConfig.socketDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        unlink(DISocketConfig.socketPath)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = DISocketConfig.socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
            pathBytes.withUnsafeBufferPointer { src in
                let raw = UnsafeMutableRawPointer(sunPath)
                raw.copyMemory(from: src.baseAddress!, byteCount: min(src.count, 104))
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            close(serverFD)
            return
        }

        guard listen(serverFD, 16) == 0 else {
            close(serverFD)
            return
        }

        isRunning = true

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        isRunning = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(DISocketConfig.socketPath)
    }

    private func acceptLoop() {
        while isRunning {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else {
                continue
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(clientFD)
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        guard let data = readAll(fd), !data.isEmpty else {
            close(fd)
            return
        }

        guard let message = try? DIProtocol.decode(data) else {
            close(fd)
            return
        }

        switch message.type {
        case .permissionRequest:
            Task { @MainActor in
                self.sessionManager.handlePermissionRequest(message) { [weak self] approved in
                    self?.sendResponse(fd: fd, approved: approved, sessionId: message.sessionId)
                }
            }

        case .question:
            Task { @MainActor in
                self.sessionManager.handleQuestionRequest(
                    message,
                    respond: { [weak self] answer in
                        self?.sendQuestionResponse(fd: fd, answer: answer, sessionId: message.sessionId)
                    },
                    cancel: { close(fd) }
                )
            }

        case .planReview:
            Task { @MainActor in
                self.sessionManager.handlePlanReview(message) { [weak self] approved, feedback in
                    self?.sendPlanResponse(fd: fd, approved: approved, feedback: feedback, sessionId: message.sessionId)
                }
            }

        default:
            Task { @MainActor in
                self.sessionManager.handleMessage(message)
            }
            close(fd)
        }
    }

    private func sendResponse(fd: Int32, approved: Bool, sessionId: String) {
        var msg = DIMessage(type: .permissionResponse, sessionId: sessionId)
        msg.approved = approved
        writeAndClose(fd: fd, message: msg)
    }

    private func sendQuestionResponse(fd: Int32, answer: String, sessionId: String) {
        var msg = DIMessage(type: .questionResponse, sessionId: sessionId)
        msg.answer = answer
        writeAndClose(fd: fd, message: msg)
    }

    private func sendPlanResponse(fd: Int32, approved: Bool, feedback: String?, sessionId: String) {
        var msg = DIMessage(type: .planResponse, sessionId: sessionId)
        msg.planApproved = approved
        msg.feedback = feedback
        writeAndClose(fd: fd, message: msg)
    }

    private func writeAndClose(fd: Int32, message: DIMessage) {
        guard let data = try? DIProtocol.encode(message) else {
            close(fd)
            return
        }
        _ = data.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return -1 }
            return send(fd, base, ptr.count, 0)
        }
        close(fd)
    }

    private func readAll(_ fd: Int32) -> Data? {
        var data = Data()
        let bufSize = 65536
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        while true {
            let n = recv(fd, buf, bufSize, 0)
            if n > 0 {
                data.append(buf, count: n)
                if n < bufSize { break }
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }
}
