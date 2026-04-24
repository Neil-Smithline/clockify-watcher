import AppKit

func formatElapsed(from start: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(start)))
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    return "\(hours):\(String(format: "%02d", minutes))"
}

extension NSColor {
    convenience init?(hex: String) {
        let stripped = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard stripped.count == 6, let value = UInt64(stripped, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
