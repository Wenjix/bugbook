import SwiftUI

/// Renders a column block as a side-by-side horizontal layout of child blocks.
struct ColumnBlockView: View {
    @ObservedObject var document: BlockDocument
    let block: Block

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(block.children) { child in
                VStack(alignment: .leading, spacing: 0) {
                    BlockCellView(document: document, block: child)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }
}
