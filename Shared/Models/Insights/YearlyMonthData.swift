//
//  YearlyMonthData.swift
//  Aidoku
//
//  Created by Skitty on 12/20/25.
//

import Foundation

enum Month: Int, CaseIterable {
    case january = 1
    case february
    case march
    case april
    case may
    case june
    case july
    case august
    case september
    case october
    case november
    case december
}

struct MonthData {
    var january: Int = 0
    var february: Int = 0
    var march: Int = 0
    var april: Int = 0
    var may: Int = 0
    var june: Int = 0
    var july: Int = 0
    var august: Int = 0
    var september: Int = 0
    var october: Int = 0
    var november: Int = 0
    var december: Int = 0

    func value(for month: Month) -> Int {
        switch month {
            case .january: january
            case .february: february
            case .march: march
            case .april: april
            case .may: may
            case .june: june
            case .july: july
            case .august: august
            case .september: september
            case .october: october
            case .november: november
            case .december: december
        }
    }

    var maxValue: Int {
        [
            january, february, march, april, may, june,
            july, august, september, october, november, december
        ].max() ?? 0
    }

    var total: Int {
        [
            january, february, march, april, may, june,
            july, august, september, october, november, december
        ].reduce(0) { $0 + $1 }
    }
}

struct YearlyMonthData {
    let year: Int
    let data: MonthData
}
