//
//  FaceBoxView.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import SwiftUI

struct FaceBoxView: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .stroke(.green.opacity(0.9), lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}