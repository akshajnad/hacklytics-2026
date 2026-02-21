//
//  Color+Hex.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//

import SwiftUI

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }

        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)

        let r, g, b: Double
        if h.count == 6 {
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        } else {
            r = 0.6; g = 0.6; b = 0.6
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
