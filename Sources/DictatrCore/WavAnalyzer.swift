import Foundation

public enum WavAnalyzer {
    // Amplitud pico de un WAV PCM 16-bit little-endian (localiza el chunk "data")
    public static func peakAmplitude(wav: Data) -> Int {
        guard let range = wav.range(of: Data("data".utf8)), range.upperBound + 4 <= wav.count else { return 0 }
        var peak = 0
        var i = range.upperBound + 4  // saltar el tamaño del chunk
        while i + 1 < wav.count {
            let lo = Int(wav[i])
            let hi = Int(Int8(bitPattern: wav[i + 1]))
            let sample = abs((hi << 8) | lo)
            if sample > peak { peak = sample }
            i += 2
        }
        return peak
    }

    // Sin permiso de micrófono, macOS entrega buffers a cero: silencio absoluto.
    // Un micro real siempre capta algo de ruido ambiente (pico > 100 de 32767).
    public static func isSilent(wav: Data) -> Bool {
        peakAmplitude(wav: wav) < 100
    }
}
