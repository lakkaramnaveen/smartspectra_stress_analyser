import Foundation
import CoreImage
import AppKit

/// Computes average frame brightness using Core Image's built-in
/// area-average filter.
///
/// Uses `CIAreaAverage` rather than a hand-rolled pixel loop — the
/// standard, efficient tool for this on Apple platforms. Its cost
/// doesn't scale with image resolution the way manually iterating every
/// pixel would, which matters here since this runs against live camera
/// frames.
///
/// Needs no new camera permission: this only analyzes frames already
/// being delivered to `AppModel.frame` for the core biometric feature.
/// Nothing new is being observed, and nothing here retains or exports
/// the image itself — only a single brightness number ever leaves this
/// function.
struct LightingAnalyzer: Sendable {
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Average luminance of an image, 0 (black) ... 1 (white), or `nil`
    /// if the frame couldn't be analyzed.
    func brightness(of image: NSImage) -> Double? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let ciImage = CIImage(cgImage: cgImage)

        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let r = Double(pixel[0]) / 255
        let g = Double(pixel[1]) / 255
        let b = Double(pixel[2]) / 255

        // Standard perceptual luminance weighting — the eye is far more
        // sensitive to green than red or blue, so a flat RGB average
        // would under-represent how bright a frame actually looks.
        return (0.299 * r) + (0.587 * g) + (0.114 * b)
    }
}
