//
//  TrackerSettingOptionViewCoordinator.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/19/22.
//

import UIKit

class TrackerSettingOptionViewCoordinator: NSObject, UIPickerViewDelegate, UIPickerViewDataSource {

    var total: Int
    var numberType: NumberType

    let pickerView = UIPickerView(frame: CGRect(x: 10, y: 40, width: 250, height: 150))

    init(total: Int = 0, numberType: NumberType = .int) {
        self.total = total
        self.numberType = numberType
        super.init()
        pickerView.delegate = self
        pickerView.dataSource = self
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        numberType == .int ? total + 1 : total * 10 + 1
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        row == 0 ? "-" : numberType == .int ? String(row) : String(format: "%g", Float(row) / 10)
    }
}
