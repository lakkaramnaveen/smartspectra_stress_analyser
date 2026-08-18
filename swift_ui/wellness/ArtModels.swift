import CoreGraphics

/// A single particle in the abstract visualization. Pure data — no
/// SwiftUI import here at all; `BiofeedbackArtView` is the only thing
/// that knows how to draw one.
struct ArtParticle: Identifiable {
    let id: Int
    var position: CGPoint
    var velocity: CGVector
    var size: CGFloat
    /// 0...1, mapped from stress — see `ParticleFieldEngine.stressHue`.
    var hue: Double
    var opacity: Double
    var age: Double
    var lifespan: Double
}
