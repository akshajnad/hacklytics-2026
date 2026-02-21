//
//  SpeakerArrowView.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//

import SwiftUI

enum ArrowDirection: String {
    case left, center, right
}

struct SpeakerArrowView: View {
    let direction: ArrowDirection

    var body: some View {
        HStack {
            if direction == .left {
                Image(systemName: "arrow.left.circle.fill")
            } else if direction == .right {
                Image(systemName: "arrow.right.circle.fill")
            } else {
                Image(systemName: "arrow.up.circle.fill")
            }
        }
        .font(.system(size: 40, weight: .bold))
        .foregroundStyle(.white.opacity(0.9))
        .shadow(radius: 10)
    }
}
