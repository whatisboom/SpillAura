import SwiftUI

/// Shared spacing, sizing, and scale constants for consistent UI across all surfaces.
enum UIConstants {
    // MARK: - Spacing
    enum Spacing {
        static let sectionGap: CGFloat = 20
        static let rowGap: CGFloat = 12
        static let tightGap: CGFloat = 8
        static let iconSliderGap: CGFloat = 6
    }

    // MARK: - Sizing
    enum Size {
        static let swatchStripWidth: CGFloat = 52
        static let swatchStripHeight: CGFloat = 32
        static let zonePreviewMaxWidth: CGFloat = 480
        static let menuBarWidth: CGFloat = 260
        static let edgeBiasSliderMaxWidth: CGFloat = 120
        static let modePickerMaxWidth: CGFloat = 160
        static let regionPickerMaxWidth: CGFloat = 160
    }

    // MARK: - ProgressView
    enum ProgressScale {
        static let inline: CGFloat = 0.6
    }

    // MARK: - Corner Radius
    enum CornerRadius {
        static let card: CGFloat = 10
        static let swatch: CGFloat = 6
        static let preview: CGFloat = 8
    }

    // MARK: - Error line limits
    enum LineLimit {
        static let statusBadge: Int = 2
    }
}
