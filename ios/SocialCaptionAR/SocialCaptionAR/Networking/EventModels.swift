//
//  EventModels.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//

import Foundation
import SwiftUI

struct CaptionEvent: Codable {
    let type: String
    let t_ms: Int?
    let text: String
    let is_final: Bool?
    let tone: ToneDTO?
    let volume: Double?

    var isFinal: Bool { is_final ?? false }
    var toneValue: Tone {
        if let t = tone { return Tone(label: t.label, confidence: t.confidence, hex: t.color_hex) }
        return Tone(label: "neutral", confidence: 0.5, hex: "#9CA3AF")
    }
    var volumeValue: Double { volume ?? 0.0 }
}

struct ToneDTO: Codable {
    let label: String
    let confidence: Double
    let color_hex: String
}

struct Tone: Equatable {
    let label: String
    let confidence: Double
    let hex: String

    var color: Color { Color(hex: hex) }
}
