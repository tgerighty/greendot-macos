import Foundation

enum UTF16Sniff {
    static func encoding(of data: Data, asciiLead: UInt8) -> String.Encoding? {
        guard data.count >= 2 else { return nil }
        let bytes = [UInt8](data.prefix(2))
        if bytes[0] == 0xFE, bytes[1] == 0xFF { return .utf16 }
        if bytes[0] == 0xFF, bytes[1] == 0xFE { return .utf16 }
        if bytes[0] == 0, bytes[1] == asciiLead { return .utf16BigEndian }
        if bytes[0] == asciiLead, bytes[1] == 0 { return .utf16LittleEndian }
        return nil
    }
}
