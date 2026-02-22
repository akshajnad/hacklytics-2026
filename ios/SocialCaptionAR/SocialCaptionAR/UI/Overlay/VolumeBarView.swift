//
//  VolumeBarView.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import SwiftUI

struct VolumeBarView: View {
    let value: Double // 0..1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.18))
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.85))
                    .frame(width: max(4, geo.size.width * CGFloat(min(max(value, 0), 1))))
            }
        }
        .frame(height: 10)
    }
}
