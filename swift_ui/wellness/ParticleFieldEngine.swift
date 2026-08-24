import CoreGraphics
import Foundation

/// Pure particle-field simulation — spawns, moves, and ages particles
/// based on the current stress reading.
///
/// No SwiftUI or Canvas import anywhere in this file. `BiofeedbackArtView`
/// is the only thing that draws these; this just decides where they are.
struct ParticleFieldEngine {

    private(set) var particles: [ArtParticle] = []
    private var nextID = 0

    let bounds: CGSize

    init(bounds: CGSize) {
        self.bounds = bounds
    }

    /// Advances the simulation by `dt` seconds, given the current
    /// stress reading (0...1).
    ///
    /// Spawn rate and particle speed both scale gently with stress —
    /// deliberately gently. A "meditative visual experience" that turns
    /// frantic at high stress works against the entire point of the
    /// feature; higher stress should read as "a little more alive,"
    /// never as an alarm.
    mutating func step(dt: Double, stressScore: Double) {
        let clampedStress = min(max(stressScore, 0), 1)

        let spawnRate = 2 + (clampedStress * 4)  // 2...6 particles/sec
        let spawnCount = Int((spawnRate * dt).rounded())
        for _ in 0..<spawnCount {
            spawnParticle(stress: clampedStress)
        }

        for index in particles.indices.reversed() {
            particles[index].age += dt
            particles[index].position.x += particles[index].velocity.dx * CGFloat(dt)
            particles[index].position.y += particles[index].velocity.dy * CGFloat(dt)

            let lifeFraction = particles[index].age / particles[index].lifespan
            particles[index].opacity = max(0, 1 - lifeFraction)

            if particles[index].age >= particles[index].lifespan {
                particles.remove(at: index)
            }
        }

        // Hard cap. A runaway particle count would both look chaotic —
        // working against "meditative" — and cost real CPU during an
        // active biometric session, which shouldn't have to compete with
        // the actual signal processing for cycles.
        if particles.count > 220 {
            particles.removeFirst(particles.count - 220)
        }
    }

    private mutating func spawnParticle(stress: Double) {
        let angle = Double.random(in: 0..<(2 * .pi))
        let speed = 8 + (stress * 14)

        particles.append(
            ArtParticle(
                id: nextID,
                position: CGPoint(x: bounds.width / 2, y: bounds.height / 2),
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                size: CGFloat.random(in: 3...9),
                hue: stressHue(for: stress),
                opacity: 1,
                age: 0,
                lifespan: Double.random(in: 4...8)
            )
        )
        nextID += 1
    }

    /// Cool teal at low stress, warming toward amber as it rises —
    /// deliberately never reaching red. Red reads as an alarm color;
    /// this is meant to feel observational, not like a warning light
    /// going off exactly when someone's already stressed.
    private func stressHue(for stress: Double) -> Double {
        0.55 - (stress * 0.44)
    }
}
