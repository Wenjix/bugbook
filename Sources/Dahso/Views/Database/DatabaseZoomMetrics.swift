import SwiftUI

enum DatabaseZoomMetrics {
    static var scale: CGFloat { EditorTypography.zoomScale }

    static func size(_ base: CGFloat) -> CGFloat {
        EditorTypography.scaled(base)
    }

    static func font(_ base: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size(base), weight: weight, design: design)
    }
}
