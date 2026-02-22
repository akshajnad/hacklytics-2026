//
//  WebSocketClient.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import Foundation

final class WebSocketClient {
    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)

    var onCaptionEvent: ((CaptionEvent) -> Void)?
    var onStatus: ((String) -> Void)?
    var onConnectionStateChange: ((Bool) -> Void)?

    func connect(url: URL) {
        disconnect()
        onStatus?("Connecting...")

        task = session.webSocketTask(with: url)
        task?.resume()

        onStatus?("Connected")
        onConnectionStateChange?(true)
        receiveLoop()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        onConnectionStateChange?(false)
        onStatus?("Disconnected")
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .failure(let err):
                self.task = nil
                self.onConnectionStateChange?(false)
                self.onStatus?("WS error: \(err.localizedDescription)")
                return

            case .success(let message):
                switch message {
                case .string(let s):
                    self.handle(text: s)
                case .data(let d):
                    if let s = String(data: d, encoding: .utf8) {
                        self.handle(text: s)
                    }
                @unknown default:
                    break
                }
            }

            self.receiveLoop()
        }
    }

    private func handle(text: String) {
        guard let data = text.data(using: .utf8) else { return }
        do {
            let ev = try JSONDecoder().decode(CaptionEvent.self, from: data)
            if ev.type == "caption_event" {
                onCaptionEvent?(CaptionEvent(
                    type: ev.type,
                    t_ms: ev.t_ms,
                    text: ev.text,
                    is_final: ev.is_final,
                    tone: ev.tone,
                    volume: ev.volume
                ))
            }
        } catch {
            // ignore non-caption messages for now
        }
    }
}
