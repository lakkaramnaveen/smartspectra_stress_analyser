import Foundation
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// Converts the rendered Markdown into a document and saves it via
/// `NSSavePanel` — the same shape as every other export in this app
/// (`SessionCSVExporter`, `HealthSyncExporter`).
///
/// ## What this deliberately does not do
///
/// It does not encrypt or password-protect the file. Rolling custom
/// encryption is a real risk in itself, and a home-grown "secure"
/// checkbox that isn't backed by anything real would be worse than no
/// checkbox — it would tell the person something is protected when it
/// isn't. The exported file is a plain, readable document, exactly as
/// transparent and inspectable as every other export in this app. If
/// the person needs a genuinely secure channel, that's a question for
/// their provider's own practice — many have a patient portal built for
/// exactly this, which is almost always the right answer, not an app
/// generating its own ad hoc "secure" file.
enum TherapistReportExporter {
    #if os(macOS)
    @MainActor
    static func exportWithSavePanel(
        markdown: String,
        suggestedName: String,
        onComplete: @escaping (Bool) -> Void
    ) {
        // RTF via `AttributedString(markdown:)` is a real, built-in,
        // reliably-supported macOS path to a formatted document —
        // opens directly in TextEdit, Word, or Pages, and prints or
        // converts to PDF with the system's own tools. Deliberately not
        // hand-rolled PDF page layout: that's real complexity with real
        // failure modes, not worth the risk for a document someone is
        // about to hand to their therapist.
        var rtfData: Data?
        if let attributed = try? AttributedString(markdown: markdown) {
            let nsAttributed = NSAttributedString(attributed)
            rtfData = nsAttributed.rtf(
                from: NSRange(location: 0, length: nsAttributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        }

        let panel = NSSavePanel()
        if rtfData != nil {
            panel.allowedContentTypes = [.rtf]
            panel.nameFieldStringValue = "\(suggestedName).rtf"
        } else {
            // Falls back to the raw Markdown as plain text rather than
            // failing the export outright if RTF conversion doesn't
            // succeed for some reason.
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "\(suggestedName).md"
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                onComplete(false)
                return
            }
            do {
                if let rtfData {
                    try rtfData.write(to: url, options: .atomic)
                } else {
                    try markdown.write(to: url, atomically: true, encoding: .utf8)
                }
                onComplete(true)
            } catch {
                print("TherapistReportExporter: failed to write — \(error.localizedDescription)")
                onComplete(false)
            }
        }
    }
    #endif
}
