import Foundation

// MARK: - SSEFrame

/// One decoded Server-Sent Events frame: the accumulated `event:` field and
/// the accumulated `data:` field (multiple `data:` lines already joined
/// with `\n`, per the SSE dispatch algorithm), either of which may be
/// absent.
struct SSEFrame: Equatable, Sendable {
    let event: String?
    let data: String?
}

// MARK: - SSEFrameParser

/// Splits a raw SSE byte stream into `SSEFrame`s per the SSE dispatch
/// algorithm (WHATWG HTML §9.2.6): a blank line dispatches the
/// accumulated frame (only if it has at least one `event:` or `data:`
/// field); lines starting with `:` are comments and are ignored; multiple
/// `data:` lines within one frame accumulate, joined by `\n`, never
/// overwritten by the last one.
///
/// Reads the byte stream one byte at a time and splits lines manually
/// instead of using `AsyncSequence.lines` — on this platform that sequence
/// does not reliably yield empty lines for blank-line event delimiters,
/// which silently merges every event of a stream into a single garbled
/// one (only the last `event:`/`data:` value ever gets parsed). This is
/// the shared fix originally made in `SSEClient`, now used by every SSE
/// consumer.
enum SSEFrameParser {

    /// Reads `bytes` until the sequence ends or `onFrame` requests a stop.
    ///
    /// - Parameters:
    ///   - bytes: The raw byte stream to parse.
    ///   - onFrame: Called synchronously once per dispatched frame. Return
    ///     `true` to stop reading further bytes (e.g. after a terminal
    ///     event) — no more frames will be produced after that.
    static func run<Bytes: AsyncSequence>(
        bytes: Bytes,
        onFrame: (SSEFrame) -> Bool
    ) async rethrows where Bytes.Element == UInt8 {
        var eventType: String?
        var dataLines: [String] = []
        var lineBytes: [UInt8] = []
        var stopped = false

        func dispatchPendingFrame() {
            guard eventType != nil || !dataLines.isEmpty else { return }
            let data = dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
            let frame = SSEFrame(event: eventType, data: data)
            eventType = nil
            dataLines.removeAll(keepingCapacity: true)
            if onFrame(frame) {
                stopped = true
            }
        }

        func consume(line: String) {
            if line.isEmpty {
                dispatchPendingFrame()
                return
            }
            // Comment lines start with ':' per spec — ignored (servers use
            // these for keep-alive pings on long-running streams).
            if line.hasPrefix(":") {
                return
            }
            guard let colonIndex = line.firstIndex(of: ":") else {
                return
            }

            let field = line[line.startIndex ..< colonIndex]
                .trimmingCharacters(in: .whitespaces)

            var value = line[line.index(after: colonIndex)...]
            // Per spec, strip at most one leading space — not full
            // trimming, which could corrupt intentional content.
            if value.first == " " {
                value = value.dropFirst()
            }

            switch field {
            case "event":
                eventType = String(value)
            case "data":
                dataLines.append(String(value))
            default:
                break
            }
        }

        for try await byte in bytes {
            guard !Task.isCancelled, !stopped else { break }

            if byte == 0x0A {
                // Strip a trailing \r so CRLF and LF line endings both work.
                if lineBytes.last == 0x0D {
                    lineBytes.removeLast()
                }
                let line = String(decoding: lineBytes, as: UTF8.self)
                lineBytes.removeAll(keepingCapacity: true)
                consume(line: line)
                if stopped { break }
            } else {
                lineBytes.append(byte)
            }
        }

        if !stopped {
            // Flush a trailing partial line with no terminating LF, then
            // any frame left pending by a missing final blank line.
            if !lineBytes.isEmpty {
                consume(line: String(decoding: lineBytes, as: UTF8.self))
            }
            dispatchPendingFrame()
        }
    }
}
