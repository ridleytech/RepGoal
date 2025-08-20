//
//  Utils.swift
//  FootballTraining
//
//  Created by Randall Ridley on 4/26/25.
//

import Foundation
import SwiftUI

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        _ = scanner.scanString("#") // skip the # if it's there

        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255

        self.init(red: r, green: g, blue: b)
    }
}

extension String {
    func trim() -> String {
        return self.trimmingCharacters(in: .whitespaces)
    }
}

enum Utils {
    static func iconForExerciseType(_ type: String) -> Image {
        switch type {
        case "Basic":
            return Image(systemName: "dumbbell.fill")

        case "Conditioning":
            return Image(systemName: "figure.run")
        default:
            return Image(systemName: "questionmark.circle.fill")
        }
    }

    static func iconForExerciseType2(_ type: String) -> Text {
        switch type {
        case "Basic":
            return Text("B")
        case "Conditioning":
            return Text("C")
        case "Supporting":
            return Text("S")
        case "Supporting":
            return Text("S")
        case "Plyometric":
            return Text("P")
        case "Sprint":
            return Text("SP")
        default:
            return Text("A")
        }
    }

    static func roundToNearestMultipleOfFive(_ number: Double) -> Double {
        let val = 5 * round(Double(number) / 5.0)

        return val
    }
}

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
