//
//  ReaderViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/22/21.
//

import UIKit
import SwiftUI
import Kingfisher

class ReaderViewController: UIPageViewController {
    
    var presentationMode: Binding<PresentationMode>
    
    let manga: Manga?
    let chapter: Chapter
    let startPage: Int
    
    var savedStandardAppearance: UINavigationBarAppearance
    var savedCompactAppearance: UINavigationBarAppearance?
    var savedScrollEdgeAppearance: UINavigationBarAppearance?
    
    var items: [UIViewController] = []
    
    var currentIndex: Int {
        guard let vc = viewControllers?.first else { return 0 }
        return items.firstIndex(of: vc) ?? 0
    }
    
    var statusBarHidden = false
    
    override var prefersStatusBarHidden: Bool {
        statusBarHidden
    }
    
    init(presentationMode: Binding<PresentationMode>, manga: Manga?, chapter: Chapter, startPage: Int) {
        self.presentationMode = presentationMode
        self.manga = manga
        self.chapter = chapter
        self.startPage = startPage
        savedStandardAppearance = UINavigationBar.appearance().standardAppearance
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let manga = manga {
            DataManager.shared.addReadHistory(forMangaId: manga.id, chapterId: chapter.id)
        }
        
        modalPresentationCapturesStatusBarAppearance = true
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(close))
        
        UINavigationBar.appearance().prefersLargeTitles = false
        
        savedCompactAppearance = UINavigationBar.appearance().compactAppearance
        savedScrollEdgeAppearance = UINavigationBar.appearance().scrollEdgeAppearance
        
        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance
        
        view.backgroundColor = .systemBackground
        view.isUserInteractionEnabled = true
        
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(toggleBarVisibility))
        singleTap.numberOfTapsRequired = 1
        view.addGestureRecognizer(singleTap)
        
        let doubleTap = UITapGestureRecognizer(target: self, action: nil)
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        
        singleTap.require(toFail: doubleTap)
        
        Task {
            await loadPages()
//            self.delegate = self
            self.dataSource = self
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        UINavigationBar.appearance().prefersLargeTitles = true
        
        UINavigationBar.appearance().standardAppearance = savedStandardAppearance
        UINavigationBar.appearance().compactAppearance = savedCompactAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = savedScrollEdgeAppearance
    }
    
    @objc func toggleBarVisibility() {
        if let navigationController = navigationController {
            if navigationController.navigationBar.alpha > 0 {
                hideBars()
            } else {
                showBars()
            }
        }
    }
    
    func showBars() {
        if let navigationController = navigationController {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.statusBarHidden = false
                NotificationCenter.default.post(name: Notification.Name("updateStatusBar"), object: nil)
                self.setNeedsStatusBarAppearanceUpdate()
            } completion: { _ in
                UIView.animate(withDuration: CATransaction.animationDuration()) {
                    navigationController.navigationBar.alpha = 1
                    self.view.backgroundColor = .systemBackground
                }
            }
        }
    }

    func hideBars() {
        if let navigationController = navigationController {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.statusBarHidden = true
                NotificationCenter.default.post(name: Notification.Name("updateStatusBar"), object: nil)
                self.setNeedsStatusBarAppearanceUpdate()
            } completion: { _ in
                UIView.animate(withDuration: CATransaction.animationDuration()) {
                    navigationController.navigationBar.alpha = 0
                    self.view.backgroundColor = .black
                }
            }
        }
    }
    
    func loadPages() async {
        if let manga = manga {
            let pages = await ProviderManager.shared.provider(for: manga.provider).getPageList(chapter: chapter)
            
            let urls = pages.map { $0.imageURL ?? "" }
    //        let urls = urlStrings.map { str -> URL in
    //            URL(string: str)!
    //        }
    //        self.preloadImages(for: self.urls)
            
            items = []
            
            DispatchQueue.main.async {
                for url in urls {
                    let c = UIViewController()
                    let zoomableView = ZoomableScrollView(frame: self.view.bounds)
                    let imageView = UIImageView(frame: zoomableView.bounds)
                    imageView.kf.indicatorType = .activity
                    imageView.kf.setImage(with: URL(string: url))
                    imageView.contentMode = .scaleAspectFit
                    zoomableView.addSubview(imageView)
                    c.view = zoomableView
                    self.items.append(c)
                }
                if self.startPage < self.items.count {
                    self.setViewControllers([self.items[self.startPage]], direction: .forward, animated: true, completion: nil)
                } else if let firstViewController = self.items.first {
                    self.setViewControllers([firstViewController], direction: .forward, animated: true, completion: nil)
                }
            }
        }
    }
    
    @objc func close() {
        if let manga = manga {
            DataManager.shared.setCurrentPage(forManga: manga.id, chapter: chapter.id, page: currentIndex)
        }
        presentationMode.wrappedValue.dismiss()
    }

}

// MARK: - DataSource
extension ReaderViewController: UIPageViewControllerDataSource {
    func pageViewController(_: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let viewControllerIndex = items.firstIndex(of: viewController) else {
            return nil
        }
        
        let nextIndex = viewControllerIndex + 1
        guard items.count > nextIndex else {
//            if let manga = manga {
//                DataManager.shared.addReadHistory(forMangaId: manga.id, chapterId: chapter.id)
//            }
            return nil
        }
        
        return items[nextIndex]
    }
    
    func pageViewController(_: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let viewControllerIndex = items.firstIndex(of: viewController) else {
            return nil
        }
        
        
        let previousIndex = viewControllerIndex - 1
        guard previousIndex >= 0, items.count > previousIndex else {
            return nil
        }
        
        return items[previousIndex]
    }
    
//    func pageViewController(_ pageViewController: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation {
//        if orientation.isLandscape {
//            self.isDoubleSided = false
//            self.setViewControllers(Array(self.items.prefix(2)), direction: .forward, animated: true, completion: nil)
//            return .mid
//        }
//        return .min
//    }
    
//    func presentationCount(for _: UIPageViewController) -> Int {
//        return items.count
//    }
//
//    func presentationIndex(for _: UIPageViewController) -> Int {
//        guard let firstViewController = viewControllers?.first,
//              let firstViewControllerIndex = items.firstIndex(of: firstViewController) else {
//                return 0
//        }
//
//        return firstViewControllerIndex
//    }
}
