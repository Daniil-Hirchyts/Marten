import Foundation

#if canImport(UIKit)
import UIKit

struct ItemCardLayoutCalculator {
    static func columnCount(for traitCollection: UITraitCollection) -> Int {
        traitCollection.horizontalSizeClass == .regular ? 3 : 2
    }

    static func itemWidth(containerWidth: CGFloat, columns: Int, spacing: CGFloat = 12) -> CGFloat {
        let rawWidth = (containerWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        return floor(max(150, min(500, rawWidth)))
    }

    static func compositionalLayout(
        containerWidth: CGFloat,
        traitCollection: UITraitCollection
    ) -> UICollectionViewLayout {
        let columns = columnCount(for: traitCollection)
        let spacing: CGFloat = 12
        let width = itemWidth(containerWidth: containerWidth, columns: columns, spacing: spacing)
        let fractionalWidth = containerWidth > 0 ? width / containerWidth : 1.0 / CGFloat(columns)

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(fractionalWidth),
            heightDimension: .fractionalWidth(fractionalWidth)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .fractionalWidth(fractionalWidth)
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            subitems: Array(repeating: item, count: columns)
        )
        group.interItemSpacing = .fixed(spacing)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)

        return UICollectionViewCompositionalLayout(section: section)
    }
}

#endif
