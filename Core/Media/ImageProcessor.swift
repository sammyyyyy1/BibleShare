import UIKit

/// Pure image resizing/encoding, split out from MediaUploader so it is testable
/// without a network or a Supabase client.
enum ImageProcessor {
    static func jpegData(from image: UIImage,
                         maxDimension: CGFloat = 1600,
                         quality: CGFloat = 0.8) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image.jpegData(compressionQuality: quality) }

        let scale = maxDimension / longest
        let target = CGSize(width: (image.size.width * scale).rounded(),
                            height: (image.size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }
}
