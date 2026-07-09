/// Deterministic RNG for the hand-drawn engine (early Phase 8 de-risk).
///
/// Bit-for-bit port of the mulberry32 generator used in the reference
/// implementation (`Prototypes/sketch-playground.html`), so tuned parameters
/// produce the same wobble in Swift as they did in the playground.
/// Verified against JS golden values in `SketchRandomTests`.
public struct SketchRandom: Sendable {
    private var state: UInt32

    public init(seed: UInt32) {
        state = seed
    }

    /// Uniform in [0, 1). Matches JS `mulberry32` exactly (Math.imul ==
    /// wrapping 32-bit multiply; `>>>` == logical shift on UInt32).
    public mutating func next() -> Double {
        state &+= 0x6D2B_79F5
        var t = (state ^ (state >> 15)) &* (state | 1)
        t = (t &+ ((t ^ (t >> 7)) &* (t | 61))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }

    /// Uniform in [-1, 1).
    public mutating func nextSigned() -> Double {
        next() * 2 - 1
    }
}

/// FNV-style 3-way hash used to derive per-stroke/per-variant seeds so every
/// element wobbles independently but reproducibly. Matches the JS `hash3`.
public func sketchHash(_ a: UInt32, _ b: UInt32, _ c: UInt32) -> UInt32 {
    var h: UInt32 = 2_166_136_261 ^ a
    h = (h &* 16_777_619) ^ b
    h = (h &* 16_777_619) ^ c
    return h
}
