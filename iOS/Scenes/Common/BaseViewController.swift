//
//  BaseViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import UIKit

class BaseViewController: UIViewController {

    private lazy var loadingAlert: UIAlertController = {
        let loadingAlert = UIAlertController(
            title: nil,
            message: NSLocalizedString("LOADING_ELLIPSIS", comment: ""),
            preferredStyle: .alert
        )
        let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
        loadingIndicator.style = .medium
        loadingIndicator.tag = 3
        loadingAlert.view.addSubview(loadingIndicator)
        return loadingAlert
    }()

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configure()
        constrain()
    }

    func configure() {}
    func constrain() {}
}

extension BaseViewController {

    /// Shows an action sheet to confirm an action before proceeding.
    func confirmAction(
        title: String,
        message: String,
        continueActionName: String = NSLocalizedString("CONTINUE", comment: ""),
        destructive: Bool = true,
        proceed: @escaping () -> Void
    ) {
        let alertView = UIAlertController(
            title: title,
            message: message,
            preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet
        )

        let action = UIAlertAction(title: continueActionName, style: destructive ? .destructive : .default) { _ in proceed() }
        alertView.addAction(action)

        alertView.addAction(UIAlertAction(title: NSLocalizedString("CANCEL", comment: ""), style: .cancel))
        present(alertView, animated: true)
    }

    /// Shows a non-interactive loading indicator.
    func showLoadingIndicator() {
        (loadingAlert.view.subviews.first(where: { $0.tag == 3 }) as? UIActivityIndicatorView)?.startAnimating()
        present(loadingAlert, animated: true, completion: nil)
    }

    /// Dismisses shown loading indicator.
    func hideLoadingIndicator() {
        loadingAlert.dismiss(animated: true)
        (loadingAlert.view.subviews.first(where: { $0.tag == 1 }) as? UIActivityIndicatorView)?.stopAnimating()
    }
}
