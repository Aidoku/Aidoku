//
//  TrackerSettingOptionView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/26/22.
//

import SwiftUI

enum TrackerSettingOptionType {
    case menu
    case counter
    case date
}

enum NumberType {
    case int
    case float
}

struct TrackerSettingOptionView: View {

    var title: String
    var type: TrackerSettingOptionType

    let options: [String]
    @Binding var selectedOption: Int?
    @Binding var count: Float?
    @Binding var total: Float?
    @Binding var date: Date?

    var numberType: NumberType = .int

    let dateFormatter: DateFormatter

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    let coordinator: TrackerSettingOptionViewCoordinator

    init(
        _ title: String,
        type: TrackerSettingOptionType = .counter,
        options: [String] = [],
        selectedOption: Binding<Int?> = Binding.constant(nil),
        count: Binding<Float?> = Binding.constant(nil),
        total: Binding<Float?> = Binding.constant(nil),
        date: Binding<Date?> = Binding.constant(nil),
        numberType: NumberType = .int
    ) {
        self.title = title
        self.type = type
        self.options = options
        self._selectedOption = selectedOption
        self._count = count
        self._total = total
        self._date = date
        self.numberType = numberType

        dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none

        coordinator = TrackerSettingOptionViewCoordinator(
            total: Int(total.wrappedValue ?? 2000), // FIXME: probably not gonna need more than 2k chapters, right?
            numberType: numberType
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .foregroundColor(Color(red: 0.52, green: 0.52, blue: 0.55))
                .font(.system(size: 14))
            HStack {
                if type == .counter {
                    Button {
                        showPicker()
                    } label: {
                        Text(
                            "\(count == nil ? "-" : String(format: numberType == .int ? "%.0f" : "%.1f", count!))" +
                            " / " +
                            "\(total == nil ? "-" : String(format: numberType == .int ? "%.0f" : "%.1f", total!))"
                        )
                            .font(.system(size: 14))
                            .foregroundColor(.black)
                    }
                }
                if type == .date {
                    ZStack {
                        DatePicker("", selection: Binding<Date>(get: { date ?? Date() }, set: {
                            if $0 > Date() {
                                date = nil
                            } else {
                                date = $0
                            }
                        }), displayedComponents: [.date])
                            .datePickerStyle(CompactDatePickerStyle())
                            .labelsHidden()
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.secondary)
                                .scaleEffect(0.85)
                                .padding([.leading], -2)
                                .padding([.trailing], -4)
                            Spacer()
                            if let date = date {
                                Text(date, formatter: dateFormatter)
                                    .font(.system(size: 14))
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        .padding([.leading, .trailing], 8)
                        .frame(width: 104, height: 38)
                        .background(Color(red: 0.93, green: 0.93, blue: 0.94))
                        .userInteractionDisabled() // hack for custom DatePicker label
                    }
                }
                if type == .menu && !options.isEmpty {
                    Menu {
                        ForEach(0..<options.count, id: \.self) { i in
                            Button {
                                selectedOption = i
                            } label: {
                                if selectedOption == i {
                                    Label(options[i], systemImage: "checkmark")
                                } else {
                                    Text(options[i])
                                }
                            }
                        }
                    } label: {
                        Text(options[selectedOption ?? 0])
                            .font(.system(size: 14))
                            .lineLimit(1)
                            .foregroundColor(.black)
                            .minimumScaleFactor(0.5)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .scaleEffect(0.8)
                            .foregroundColor(.black)
                    }
                }
            }
            .padding([.leading, .trailing], 8)
            .frame(width: 104, height: 38)
            .background(Color(red: 0.93, green: 0.93, blue: 0.94))
            .cornerRadius(8)
        }
    }

    func showPicker() {
        coordinator.pickerView.selectRow(numberType == .int ? Int(count ?? 0) : Int((count ?? 0) * 10), inComponent: 0, animated: false)

        let alert = UIAlertController(title: title, message: "\n\n\n\n\n\n\n\n", preferredStyle: .alert)

        alert.view.addSubview(coordinator.pickerView)
        coordinator.pickerView.translatesAutoresizingMaskIntoConstraints = false
        coordinator.pickerView.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor).isActive = true
        coordinator.pickerView.centerYAnchor.constraint(equalTo: alert.view.centerYAnchor, constant: -5).isActive = true
        coordinator.pickerView.widthAnchor.constraint(equalToConstant: 250).isActive = true
        coordinator.pickerView.heightAnchor.constraint(equalToConstant: 150).isActive = true

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
            let pickerValue = coordinator.pickerView.selectedRow(inComponent: 0)
            let result = numberType == .int ? Float(pickerValue) : Float(pickerValue) / 10
            count = result == 0 ? nil : result
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("CANCEL", comment: ""), style: .cancel, handler: nil))
        (UIApplication.shared.delegate as? AppDelegate)?.visibleViewController?.present(alert, animated: true)
    }
}
