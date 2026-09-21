import AppKit

struct ResizePreviewCornerRadii {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomRight: CGFloat
    let bottomLeft: CGFloat

    static func uniform(_ radius: CGFloat) -> ResizePreviewCornerRadii {
        ResizePreviewCornerRadii(
            topLeft: radius,
            topRight: radius,
            bottomRight: radius,
            bottomLeft: radius
        )
    }
}

func windowResizePreviewCornerRadius(for rect: CGRect) -> CGFloat {
    0
}
