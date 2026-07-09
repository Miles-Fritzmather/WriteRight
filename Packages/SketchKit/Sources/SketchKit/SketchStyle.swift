/// Every tunable of the hand-drawn look, in one value type.
///
/// Defaults are the parameters Miles locked in the HTML playground on
/// 2026-07-07. Distances are in points, times in seconds (the playground
/// used ms for `strokePause`; converted here).
public struct SketchStyle: Sendable, Equatable {
    // MARK: Wobble — the hand-drawn displacement
    /// Arc-length resampling interval before wobbling.
    public var spacing: Double = 5
    /// Max perpendicular displacement of the ideal path.
    public var amplitude: Double = 2.2
    /// Arc-length distance between noise control points; longer = lazier.
    public var wavelength: Double = 38
    /// Random offset applied to stroke endpoints (blended over ~25pt).
    public var jitter: Double = 2.5
    /// Multiplier on amplitude+jitter for label strokes — text wobbles less
    /// than shapes so it stays legible. Subtext uses 0.6× of this again.
    public var labelWobble: Double = 0.35

    // MARK: Boil — the idle "alive" cycle
    /// How often the pre-generated wobble variants swap.
    public var boilFps: Double = 2
    /// Number of pre-generated wobble variants per element/state.
    public var variants: Int = 3

    // MARK: Ink — the ribbon that makes it read as ink, not a shaky vector
    public var inkWidth: Double = 3.4
    /// Noise-modulated width variance (0 = uniform width).
    public var widthVariance: Double = 0.5
    /// Length of the pen-pressure taper at both stroke ends.
    public var taper: Double = 14
    /// Second, thinner offset pass — the "sketched over" look (border only).
    public var ghost: Bool = true
    public var ghostAlpha: Double = 0.28
    public var ghostOffset: Double = 2

    // MARK: Scribble — the write-on entrance
    /// Pen travel speed, points per second.
    public var penSpeed: Double = 1400
    /// Pause between strokes, seconds (playground: 60 ms).
    public var strokePause: Double = 0.06

    // MARK: Press state
    public var pressWidthMultiplier: Double = 1.35
    public var pressSquash: Double = 0.94
    public var hatchSpacing: Double = 13

    // MARK: Border shape
    /// >= 1: one continuous swoop around a rounded rect.
    /// < 1: four overshooting side strokes (sharp sketchbook box).
    public var cornerRadius: Double = 14
    /// Sharp mode: overshoot past each corner. Swoop mode: closing overlap.
    public var overshoot: Double = 10

    // MARK: Palette (hex, resolved to platform colors at the UI layer)
    public var inkHex: String = "#2b2723"
    public var paperHex: String = "#f7f2e7"

    public init() {}
}
