//
//  Copyright 2025 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import ReadiumShared

/// Positions Service for an EPUB from its `readingOrder` and `fetcher`.
///
/// The `presentation` is used to apply different calculation strategy if the resource has a
/// reflowable or fixed layout.
///
/// https://github.com/readium/architecture/blob/master/models/locators/best-practices/format.md#epub
/// https://github.com/readium/architecture/issues/101
///
public actor EPUBPositionsService: PositionsService {
    public static func makeFactory(reflowableStrategy: ReflowableStrategy = .recommended) -> (PublicationServiceContext) -> EPUBPositionsService? {
        { context in
            EPUBPositionsService(
                readingOrder: context.manifest.readingOrder,
                presentation: context.manifest.metadata.presentation,
                pageList: context.manifest.subcollections["pageList"]?.first?.links ?? [],
                container: context.container,
                reflowableStrategy: reflowableStrategy
            )
        }
    }

    /// Strategy used to calculate the number of positions in a reflowable resource.
    ///
    /// Note that a fixed-layout resource always has a single position.
    public enum ReflowableStrategy {
        /// Use the archive entry length (whether it is compressed or stored) and split it by the given `pageLength`.
        case archiveEntryLength(pageLength: Int)

        /// Recommended historical strategy: archive entry length split by 1024 bytes pages.
        ///
        /// This strategy is used by Adobe RMSDK as well.
        /// See https://github.com/readium/architecture/issues/123
        public static var recommended = archiveEntryLength(pageLength: 1024)

        /// Returns the number of positions in the given `resource` according to the strategy.
        func positionCount(for link: Link, resource: Resource) async -> Int {
            switch self {
            case let .archiveEntryLength(pageLength):
                let length = await {
                    if let l = try? await resource.properties().map({ $0.archive?.entryLength }).get() {
                        return l
                    } else if let l = try? await resource.estimatedLength().get() {
                        return l
                    } else {
                        return 0
                    }
                }()
                return max(1, Int(ceil(Double(length) / Double(pageLength))))
            }
        }
    }

    private let readingOrder: [Link]
    private let presentation: Presentation
    private let pageList: [Link]
    private let container: Container
    private let reflowableStrategy: ReflowableStrategy

    init(
        readingOrder: [Link],
        presentation: Presentation,
        pageList: [Link],
        container: Container,
        reflowableStrategy: ReflowableStrategy
    ) {
        self.readingOrder = readingOrder
        self.presentation = presentation
        self.pageList = pageList
        self.container = container
        self.reflowableStrategy = reflowableStrategy
    }

    private var _positionsByReadingOrder: ReadResult<[[Locator]]>?

    public func positionsByReadingOrder() async -> ReadResult<[[Locator]]> {
        if _positionsByReadingOrder == nil {
            _positionsByReadingOrder = await .success(computePositionsByReadingOrder())
        }
        return _positionsByReadingOrder!
    }

    private func computePositionsByReadingOrder() async -> [[Locator]] {
        var lastPositionOfPreviousResource = 0
        var positions = await readingOrder.asyncMap { link -> [Locator] in
            let (lastPosition, positions): (Int, [Locator]) = await {
                if presentation.layout(of: link) == .fixed {
                    return makePositions(ofFixedResource: link, from: lastPositionOfPreviousResource)
                } else {
                    return await makePositions(ofReflowableResource: link, from: lastPositionOfPreviousResource)
                }
            }()
            lastPositionOfPreviousResource = lastPosition
            return positions
        }

        // Calculates totalProgression
        let totalPageCount = await positions.asyncMap(\.count).reduce(0, +)
        if totalPageCount > 0 {
            positions = positions.map { locators in
                locators.map { locator in
                    locator.copy(locations: {
                        if let position = $0.position {
                            $0.totalProgression = Double(position - 1) / Double(totalPageCount)
                        }
                    })
                }
            }
        }

        return positions
    }

    private func makePositions(ofFixedResource link: Link, from startPosition: Int) -> (Int, [Locator]) {
        let position = startPosition + 1
        let positions = [
            makeLocator(
                for: link,
                progression: 0,
                position: position
            ),
        ]
        return (position, positions)
    }

    private func makePositions(ofReflowableResource link: Link, from startPosition: Int) async -> (Int, [Locator]) {
        let href = link.href
        var startIndexPosition = startPosition
        let positionRange = pageList
            .filter { $0.href.hasPrefix(href) }
            .compactMap { Int($0.title ?? "") }
        let positionCount = pageList.filter { $0.href.hasPrefix(href) }.count

        if !positionRange.isEmpty {
            startIndexPosition = positionRange.first!
        }

        let skippedPages = findMissingNumbersUsingXor(numbers: positionRange)

        let positions = (0..<positionCount).compactMap { position -> Locator? in
            let locatorPosition = startIndexPosition + position
            let progression = 1.0 / Double(positionCount) * Double(position)

            if skippedPages.contains(locatorPosition) { return nil }
            print("Make position \(position) + startIndex: \(startIndexPosition) = \(locatorPosition), positionRange: \(positionRange), progression: \(progression), count: \(positionCount), href: \(href))")
            return Locator(
                href: AnyURL(string: href)!,
                mediaType: link.mediaType ?? .html,
                title: link.title,
                locations: .init(
                    progression: progression,
                    position: locatorPosition
                )
            )
        }

        return (startPosition, positions)
    }

    /**
     Finds missing numbers in a list of increasing numbers.
     According to the Content Team, it is possible to have skipped page numbers in an EPUB page-list.
     (These are white/empty pages in a PDF that have been removed for EPUB.)
     e.g., [1, 2, 3, 5, 8, 9] -> Pages 4 and 7 are missing.
     This function identifies the missing numbers and skips them when creating `Publication.positions()`.
     */
    private func findMissingNumbersUsingXor(numbers: [Int]) -> [Int] {
        guard !numbers.isEmpty else { return [] }

        let min = numbers.min()!
        let max = numbers.max()!

        var xorRange = 0
        for num in min...max {
            xorRange ^= num
        }

        var xorList = 0
        for num in numbers {
            xorList ^= num
        }

        let fullRange = Set(min...max)
        let actualNumbers = Set(numbers)

        return fullRange.subtracting(actualNumbers).sorted()
    }

    private func makeLocator(for link: Link, progression: Double, position: Int) -> Locator {
        Locator(
            href: link.url(),
            mediaType: link.mediaType ?? .html,
            title: link.title,
            locations: .init(
                progression: progression,
                position: position
            )
        )
    }
}
