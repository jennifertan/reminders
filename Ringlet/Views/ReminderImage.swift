import SwiftUI
import UIKit

/// A reminder's picture: your own photo, or a symbol on a colored tile.
struct ReminderImage: View {
    let photo: Data?
    let symbol: String
    let hue: Double
    var size: CGFloat = 52

    @Environment(\.colorScheme) private var colorScheme

    init(_ reminder: Reminder, size: CGFloat = 52) {
        photo = reminder.photo
        symbol = reminder.symbol
        hue = reminder.hue
        self.size = size
    }

    init(photo: Data?, symbol: String, hue: Double, size: CGFloat = 52) {
        self.photo = photo
        self.symbol = symbol
        self.hue = hue
        self.size = size
    }

    var body: some View {
        Group {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    tileColor
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(symbolColor)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .accessibilityHidden(true)
    }

    private var tileColor: Color {
        colorScheme == .dark
            ? Color(hue: hue, saturation: 0.35, brightness: 0.28)
            : Color(hue: hue, saturation: 0.18, brightness: 0.96)
    }

    private var symbolColor: Color {
        colorScheme == .dark
            ? Color(hue: hue, saturation: 0.45, brightness: 0.92)
            : Color(hue: hue, saturation: 0.75, brightness: 0.55)
    }
}

/// A picture you can pick for a reminder without using a photo.
struct SymbolOption: Hashable {
    let symbol: String
    let hue: Double
}

enum ReminderSymbols {
    private static let raw: [(String, Double)] = [
        ("pills.fill", 0.97), ("drop.fill", 0.56), ("pawprint.fill", 0.08), ("phone.fill", 0.72),
        ("briefcase.fill", 0.62), ("birthday.cake.fill", 0.9), ("sun.max.fill", 0.12), ("cross.case.fill", 0.0),
        ("dollarsign.circle.fill", 0.38), ("bell.fill", 0.48), ("dumbbell.fill", 0.03), ("leaf.fill", 0.3),
        ("cart.fill", 0.8), ("book.fill", 0.66), ("car.fill", 0.58), ("house.fill", 0.18),
        ("fork.knife", 0.05), ("graduationcap.fill", 0.68), ("heart.fill", 0.95), ("bed.double.fill", 0.7),
    ]

    static let all: [SymbolOption] = raw.map { SymbolOption(symbol: $0.0, hue: $0.1) }
}

/// Shrinks a picked photo so the store stays small.
enum PhotoResizer {
    static func jpeg(from data: Data, maxSide: CGFloat = 900) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
