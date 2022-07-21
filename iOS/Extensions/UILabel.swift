import UIKit

// MARK: - Check if UILabel fits
extension UILabel {
    var isTruncated: Bool {
        guard let title = text, let font = font else { return false }

        let size: CGSize = (title as NSString).boundingRect(
            with: CGSize(width: frame.size.width, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: [.font: font],
            context: nil
        ).size

        return size.height > bounds.size.height
    }
}

// MARK: - Sizing text to fit labels
extension UILabel {
    public func fontSizeToFit(maxFontSize: CGFloat = 100, minFontScale: CGFloat = 0.1, rectSize: CGSize? = nil) {
        guard let unwrappedText = self.text else {
            return
        }

        let newFontSize = fontSizeThatFits(text: unwrappedText, maxFontSize: maxFontSize, minFontScale: minFontScale, rectSize: rectSize)
        font = font.withSize(newFontSize)
    }
    
    public func fontSizeThatFits(text string: String, maxFontSize: CGFloat = 100, minFontScale: CGFloat = 0.1, rectSize: CGSize? = nil) -> CGFloat {
        let maxFontSize = maxFontSize.isNaN ? 100 : maxFontSize
        let minFontScale = minFontScale.isNaN ? 0.1 : minFontScale
        let minimumFontSize = maxFontSize * minFontScale
        let rectSize = rectSize ?? bounds.size
        guard !string.isEmpty else {
            return self.font.pointSize
        }

        let constraintSize = numberOfLines == 1
            ? CGSize(width: CGFloat.greatestFiniteMagnitude, height: rectSize.height)
            : CGSize(width: rectSize.width, height: CGFloat.greatestFiniteMagnitude)
        
        let calculatedFontSize = binarySearch(string: string, minSize: minimumFontSize, maxSize: maxFontSize, size: rectSize, constraintSize: constraintSize)
        return (calculatedFontSize * 10.0).rounded(.down) / 10.0
    }
}

// MARK: - Resizing label backend
extension UILabel {
    private func currentAttributedStringAttributes() -> [NSAttributedString.Key: Any] {
        var newAttributes = [NSAttributedString.Key: Any]()
        attributedText?.enumerateAttributes(in: NSRange(0..<(text?.count ?? 0)), options: .longestEffectiveRangeNotRequired, using: { attributes, _, _ in
            newAttributes = attributes
        })
        return newAttributes
    }

    private enum FontSizeState {
        case fit, tooBig, tooSmall
    }

    private func binarySearch(string: String, minSize: CGFloat, maxSize: CGFloat, size: CGSize, constraintSize: CGSize) -> CGFloat {
        let fontSize = (minSize + maxSize) / 2
        var attributes = currentAttributedStringAttributes()
        attributes[NSAttributedString.Key.font] = font.withSize(fontSize)

        let rect = string.boundingRect(with: constraintSize, options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
        let state = numberOfLines == 1 ? singleLineSizeState(rect: rect, size: size) : multiLineSizeState(rect: rect, size: size)

        // if the search range is smaller than 0.1 of a font size we stop
        // returning either side of min or max depending on the state
        let diff = maxSize - minSize
        guard diff > 0.1 else {
            switch state {
            case .tooSmall:
                return maxSize
            default:
                return minSize
            }
        }

        switch state {
        case .fit: return fontSize
        case .tooBig: return binarySearch(string: string, minSize: minSize, maxSize: fontSize, size: size, constraintSize: constraintSize)
        case .tooSmall: return binarySearch(string: string, minSize: fontSize, maxSize: maxSize, size: size, constraintSize: constraintSize)
        }
    }

    private func singleLineSizeState(rect: CGRect, size: CGSize) -> FontSizeState {
        if rect.width >= size.width + 5 && rect.width <= size.width {
            return .fit
        } else if rect.width > size.width {
            return .tooBig
        } else {
            return .tooSmall
        }
    }

    private func multiLineSizeState(rect: CGRect, size: CGSize) -> FontSizeState {
        // if rect within 10 of size
        if rect.height < size.height + 5 &&
           rect.height > size.height - 5 &&
           rect.width > size.width + 5 &&
           rect.width < size.width - 5 {
            return .fit
        } else if rect.height > size.height || rect.width > size.width {
            return .tooBig
        } else {
            return .tooSmall
        }
    }
}


