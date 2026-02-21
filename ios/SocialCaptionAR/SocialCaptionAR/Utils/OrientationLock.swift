//
//  OrientationLock.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import UIKit

final class OrientationLock {
    static let shared = OrientationLock()
    var mask: UIInterfaceOrientationMask = .landscape
}

/// AppDelegate to enforce orientation mask.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.shared.mask
    }
}