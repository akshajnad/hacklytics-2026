//
//  ToneBadgeView.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import SwiftUI

struct ToneBadgeView: View {
    let tone: Tone

    var body: some View {
        Text(tone.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tone.color.opacity(0.9))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}
