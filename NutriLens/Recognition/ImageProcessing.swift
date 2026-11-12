import UIKit

enum ImageProcessing {
    /// Redraws `image` upright (applying its EXIF orientation) and no larger than `maxDimension`
    /// points on its longest side, so classifiers and storage get a small, correctly rotated image.
    static func normalized(_ image: UIImage, maxDimension: CGFloat = 1024) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// A small JPEG thumbnail for the meal log.
    static func thumbnailJPEG(_ image: UIImage, maxDimension: CGFloat = 480) -> Data? {
        normalized(image, maxDimension: maxDimension).jpegData(compressionQuality: 0.7)
    }
}
