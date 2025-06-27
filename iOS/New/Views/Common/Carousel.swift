//
//  Carousel.swift
//  Aidoku
//
//  Created by Skitty on 10/14/23.
//

import SwiftUI

struct Carousel<Data: RandomAccessCollection, Content: View>: UIViewRepresentable {
    let data: Data
    let content: (Int, Data.Element) -> Content
    let autoScrollInterval: TimeInterval?
    @Binding var currentPage: Int
    @Binding var autoScrollPaused: Bool

    private let layout: UICollectionViewFlowLayout

    init(
        _ data: Data,
        autoScrollInterval: TimeInterval? = nil,
        itemWidth: CGFloat? = nil,
        itemHeight: CGFloat? = nil,
        currentPage: Binding<Int> = .constant(0),
        autoScrollPaused: Binding<Bool> = .constant(false),
        content: @escaping (Int, Data.Element) -> Content
    ) {
        self.data = data
        self.content = content
        self.autoScrollInterval = autoScrollInterval
        self._currentPage = currentPage
        self._autoScrollPaused = autoScrollPaused
        self.layout = CarouselScreenSizingCollectionViewLayout(
            itemWidth: itemWidth,
            itemHeight: itemHeight
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> CarouselCollectionView {
        let collectionView = CarouselCollectionView(frame: .zero, collectionViewFlowLayout: layout)
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(
            UIHostingCollectionViewCell<Content>.self,
            forCellWithReuseIdentifier: "UIHostingCollectionViewCell"
        )
        collectionView.carouselDataSource = context.coordinator
        collectionView.isScrollEnabled = data.count > 1
        if let autoScrollInterval, data.count > 1 {
            collectionView.isAutoScrollEnabled = true
            collectionView.autoScrollInterval = autoScrollInterval
        }
        return collectionView
    }

    func updateUIView(_ uiView: CarouselCollectionView, context: Context) {
        if autoScrollInterval != nil {
            uiView.isAutoScrollEnabled = !autoScrollPaused
        }
        uiView.reloadData()
    }

    @MainActor
    class Coordinator: NSObject, CarouselCollectionViewDataSource {
        var parent: Carousel

        var numberOfItems: Int {
            parent.data.count
        }

        init(_ parent: Carousel) {
            self.parent = parent
        }

        func carouselCollectionView(
            _ carouselCollectionView: CarouselCollectionView,
            cellForItemAt index: Int,
            fakeIndexPath: IndexPath
        ) -> UICollectionViewCell {
            // swiftlint:disable force_cast
            let cell = carouselCollectionView.dequeueReusableCell(
                withReuseIdentifier: "UIHostingCollectionViewCell",
                for: fakeIndexPath
            ) as! UIHostingCollectionViewCell<Content>
            cell.configure(with: parent.content(index, parent.data[index as! Data.Index]))
            return cell
            // swiftlint:enable force_cast
        }

        func pageDidChange(_ page: Int) {
            parent.currentPage = page
        }
    }
}

class UIHostingCollectionViewCell<Content: View>: UICollectionViewCell {
    var hostingController: UIHostingController<Content>?

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with view: Content) {
        if let hostingController {
            hostingController.rootView = view
        } else {
            let hostingController = UIHostingController(rootView: view, ignoreSafeArea: true)
            self.hostingController = hostingController
            hostingController.view.backgroundColor = .clear
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(hostingController.view)

            NSLayoutConstraint.activate([
                hostingController.view.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                hostingController.view.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                hostingController.view.widthAnchor.constraint(equalTo: contentView.widthAnchor),
                hostingController.view.heightAnchor.constraint(equalTo: contentView.heightAnchor)
            ])
        }
    }
}

@MainActor
protocol CarouselCollectionViewDataSource: AnyObject {
    var numberOfItems: Int { get }

    func carouselCollectionView(
        _ carouselCollectionView: CarouselCollectionView,
        cellForItemAt index: Int,
        fakeIndexPath: IndexPath
    ) -> UICollectionViewCell

    func pageDidChange(_ page: Int)
}

class CarouselScreenSizingCollectionViewLayout: UICollectionViewFlowLayout {
    let itemWidth: CGFloat?
    let itemHeight: CGFloat?

    init(itemWidth: CGFloat?, itemHeight: CGFloat?) {
        self.itemWidth = itemWidth
        self.itemHeight = itemHeight
        super.init()
        itemSize = CGSize(
            width: itemWidth ?? UIScreen.main.bounds.size.width,
            height: itemHeight ?? UIScreen.main.bounds.size.height
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateItemSize() {
        let width: CGFloat = {
            if let width = self.itemWidth {
                return width
            } else {
                guard let window = UIApplication.shared.firstKeyWindow else {
                    return UIScreen.main.bounds.width
                }
                let leftPadding = window.safeAreaInsets.left
                let rightPadding = window.safeAreaInsets.right
                return window.bounds.width - leftPadding - rightPadding
            }
        }()
        let height: CGFloat = {
            if let height = self.itemHeight {
                return height
            } else {
                guard let window = UIApplication.shared.firstKeyWindow else {
                    return UIScreen.main.bounds.height
                }
                let topPadding = window.safeAreaInsets.top
                let bottomPadding = window.safeAreaInsets.bottom
                return window.bounds.height - topPadding - bottomPadding
            }
        }()
        itemSize = CGSize(width: width, height: height)
    }
}

class CarouselCollectionView: UICollectionView {
    weak var carouselDataSource: CarouselCollectionViewDataSource?

    let flowLayout: UICollectionViewFlowLayout
    var autoScrollInterval: TimeInterval = 0

    var isAutoScrollEnabled: Bool = false {
        didSet {
            if isAutoScrollEnabled {
                scheduleTimer()
            } else {
                stopTimer()
            }
        }
    }

    var currentPage: Int {
        get {
            let center = CGPoint(x: contentOffset.x + (frame.width / 2), y: frame.height / 2)
            if let fakeIndexPath = indexPathForItem(at: center) {
                return getRealIndex(fakeIndexPath)
            } else {
                return 0
            }
        }
        set {
            assert((0..<numberOfItems).contains(newValue))
            setFakePage(newValue + 1)
        }
    }

    var fakeCurrentPage: Int {
        get {
            guard flowLayout.itemSize.width > 0 else { return 0 }
            return Int(ceil(contentOffset.x / flowLayout.itemSize.width))
        }
        set {
            setFakePage(newValue, animated: false)
        }
    }

    private var hasInitializedFirstPage = false
    private var autoScrollTimer: Timer?

    private var numberOfItems: Int {
        carouselDataSource?.numberOfItems ?? 0
    }

    private var fakeNumberOfItems: Int {
        if let realNumberOfItems = carouselDataSource?.numberOfItems,
           realNumberOfItems > 0
        {
            return realNumberOfItems + 2
        } else {
            return 0
        }
    }

    init(frame: CGRect, collectionViewFlowLayout layout: UICollectionViewFlowLayout) {
        flowLayout = layout
        super.init(frame: frame, collectionViewLayout: layout)
        delegate = self
        dataSource = self
        isPagingEnabled = true
        flowLayout.scrollDirection = .horizontal
        flowLayout.minimumLineSpacing = 0
        flowLayout.minimumInteritemSpacing = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func getRealIndex(_ fakeIndexPath: IndexPath) -> Int {
        guard let realNumberOfItems = carouselDataSource?.numberOfItems else {
            return 0
        }

        if fakeIndexPath.row == realNumberOfItems + 1 {
            return 0
        }

        if fakeIndexPath.row == 0 {
            return realNumberOfItems - 1
        }

        return fakeIndexPath.row - 1
    }

    private func setFakePage(_ fakePage: Int, animated: Bool = false) {
        guard
            numberOfItems > 0,
            (0..<fakeNumberOfItems).contains(fakePage)
        else { return }
        let newContentOffset = CGPoint(x: flowLayout.itemSize.width * CGFloat(fakePage), y: 0)
        setContentOffset(newContentOffset, animated: animated)
    }

//    func setCurrentPage(_ page: Int, animated: Bool = false) {
//        precondition((0..<numberOfItems).contains(page))
//        setFakePage(page + 1, animated: animated)
//    }

    private func loopItems() {
        let page = fakeCurrentPage
        if page == 0 {
            setFakePage(fakeNumberOfItems - 2)
        } else if page == fakeNumberOfItems {
            setFakePage(1)
        }
    }

    // MARK: Autoscrolling

    private func scheduleTimer(delay: TimeInterval = 0) {
        guard isAutoScrollEnabled else { return }
        autoScrollTimer?.invalidate()
        autoScrollTimer = Timer.scheduledTimer(
            withTimeInterval: autoScrollInterval + delay,
            repeats: false
        ) {  [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.scrollToNextElement()
            }
        }
    }

    private func stopTimer() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    private func scrollToNextElement() {
        guard fakeNumberOfItems > 0 else { return }
        if fakeCurrentPage == fakeNumberOfItems - 1 {
            setFakePage(1)
        }
        setFakePage(fakeCurrentPage + 1, animated: true)
        scheduleTimer()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        guard let flowLayout = flowLayout as? CarouselScreenSizingCollectionViewLayout else { return }
        let page = fakeCurrentPage
        flowLayout.updateItemSize()
        setFakePage(page)
    }
}

extension CarouselCollectionView: UIScrollViewDelegate, UICollectionViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        loopItems()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        loopItems()
        scheduleTimer()
        carouselDataSource?.pageDidChange(fakeCurrentPage % numberOfItems)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        scheduleTimer(delay: 3)
    }
}

extension CarouselCollectionView: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if fakeNumberOfItems > 0 && !hasInitializedFirstPage {
            currentPage = 0
            hasInitializedFirstPage = true
        }
        return fakeNumberOfItems
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let carouselDataSource else { return UICollectionViewCell() }
        let index = getRealIndex(indexPath)
        return carouselDataSource.carouselCollectionView(self, cellForItemAt: index, fakeIndexPath: indexPath)
    }
}
