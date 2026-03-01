import Foundation

/// Represents inline formatting styles that can be applied to text ranges.
enum InlineStyleType: Equatable {
    case bold
    case italic
    case code
    case strikethrough
    case link(url: String)
}

/// A range of text with an associated inline style.
struct InlineStyle: Equatable {
    var type: InlineStyleType
    var range: NSRange
}
