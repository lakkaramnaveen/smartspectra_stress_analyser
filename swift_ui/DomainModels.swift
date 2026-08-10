import SwiftUI

// MARK: - Design System Colors (Apple-Like Palette)

enum BrandColor {
    // Primary Blue (Trust, Focus, Actions)
    static let primaryBlue = Color(red: 0.0, green: 0.478, blue: 1.0)       // #007AFF
    static let lightBlue = Color(red: 0.341, green: 0.761, blue: 1.0)       // #56C2FF
    
    // Mint (Wellness, Success)
    static let mint = Color(red: 0.102, green: 0.784, blue: 0.616)          // #1AC89A
    static let lightMint = Color(red: 0.4, green: 0.9, blue: 0.8)           // #66E5CC
    
    // Coral (Energy, Alerts)
    static let coral = Color(red: 1.0, green: 0.365, blue: 0.424)           // #FF5D6C
    static let lightCoral = Color(red: 1.0, green: 0.6, blue: 0.65)         // #FF9AA6
    
    // Amber (Caution, Attention)
    static let amber = Color(red: 1.0, green: 0.647, blue: 0.0)             // #FFA500
    static let lightAmber = Color(red: 1.0, green: 0.8, blue: 0.2)          // #FFCC33
    
    // Teal (Sophistication, Depth)
    static let teal = Color(red: 0.2, green: 0.68, blue: 0.78)              // #33AEC8
    static let lightTeal = Color(red: 0.4, green: 0.8, blue: 0.9)           // #66CCFF
    
    // Neutrals (Modern Dark Gray)
    static let slate = Color(red: 0.105, green: 0.110, blue: 0.116)         // #1B1C1D
    static let darkGray = Color(red: 0.17, green: 0.17, blue: 0.18)         // #2B2B2E
    static let mediumGray = Color(red: 0.24, green: 0.24, blue: 0.26)       // #3D3D42
    static let lightGray = Color(red: 0.94, green: 0.94, blue: 0.96)        // #F0F0F5
}

// MARK: - Spacing System (8-Point Grid)

enum Spacing {
    static let xs: CGFloat = 4      // Micro
    static let sm: CGFloat = 8      // Base
    static let md: CGFloat = 12     // 1.5x
    static let lg: CGFloat = 16     // 2x
    static let xl: CGFloat = 24     // 3x
    static let xxl: CGFloat = 32    // 4x
    static let huge: CGFloat = 48   // 6x
}

// MARK: - Domain Models (Unchanged Structure, Better Naming)

struct VitalReading: Equatable {
    let timestamp: Date
    let heartRate: Double
    let breathingRate: Double
    let eda: Double
}

struct StressSample: Equatable {
    let value: Double
    let timestamp: Date
}

struct GazePoint: Equatable {
    var x: Double = 0.5
    var y: Double = 0.5
    var confidence: Double = 0.0
    
    static let center = GazePoint(x: 0.5, y: 0.5, confidence: 0.0)
}

struct Balloon: Identifiable, Equatable {
    let id: UUID
    var position: CGPoint
    let diameter: CGFloat
    let color: Color
    var velocity: CGFloat
}

struct GameSessionStats: Equatable {
    var balloonsPopped: Int = 0
    var score: Int = 0
    var elapsedSeconds: Double = 0.0
}

struct SessionStats: Equatable {
    var startedAt: Date = Date()
    var elapsedSeconds: Double = 0.0
    var peakStress: Double = 0.0
    var averageStress: Double = 0.0
}

// MARK: - Stress Level Classification

enum StressLevel: String, CaseIterable {
    case calm, moderate, elevated, critical
    
    var label: String {
        switch self {
        case .calm: return "Calm"
        case .moderate: return "Moderate"
        case .elevated: return "Elevated"
        case .critical: return "Critical"
        }
    }
    
    var icon: String {
        switch self {
        case .calm: return "leaf.fill"
        case .moderate: return "wind"
        case .elevated: return "flame.fill"
        case .critical: return "exclamationmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .calm: return BrandColor.mint
        case .moderate: return BrandColor.lightBlue
        case .elevated: return BrandColor.amber
        case .critical: return BrandColor.coral
        }
    }
    
    static func classify(_ score: Double) -> StressLevel {
        switch score {
        case ..<0.3: return .calm
        case ..<0.6: return .moderate
        case ..<0.8: return .elevated
        default: return .critical
        }
    }
}

// MARK: - Emotional State Classification

enum EmotionalState: String, CaseIterable, Equatable {
    case calm, focused, anxious, stressed
    
    var label: String {
        switch self {
        case .calm: return "Calm"
        case .focused: return "Focused"
        case .anxious: return "Anxious"
        case .stressed: return "Stressed"
        }
    }
    
    var icon: String {
        switch self {
        case .calm: return "leaf.fill"
        case .focused: return "target"
        case .anxious: return "exclamationmark.circle.fill"
        case .stressed: return "flame.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .calm: return BrandColor.mint
        case .focused: return BrandColor.primaryBlue
        case .anxious: return BrandColor.amber
        case .stressed: return BrandColor.coral
        }
    }
}

// MARK: - Game Difficulty Levels

enum GameDifficulty: String, CaseIterable {
    case easy, medium, hard, extreme
    
    var id: String { self.rawValue }
    
    var label: String {
        rawValue.capitalized
    }
    
    var balloonSpawnInterval: TimeInterval {
        switch self {
        case .easy: return 1.2
        case .medium: return 0.8
        case .hard: return 0.5
        case .extreme: return 0.3
        }
    }
    
    var balloonVelocityRange: ClosedRange<CGFloat> {
        switch self {
        case .easy: return 40...80
        case .medium: return 60...120
        case .hard: return 80...150
        case .extreme: return 100...180
        }
    }
    
    var pointMultiplier: Double {
        switch self {
        case .easy: return 1.0
        case .medium: return 2.0
        case .hard: return 3.0
        case .extreme: return 5.0
        }
    }
}
