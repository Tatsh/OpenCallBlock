//
//  DatabaseManager.swift
//  CallDataKit
//
//  Created by Chris Ballinger on 10/27/17.
//  Copyright © 2017 Chris Ballinger. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift
import CallKit

private struct Constants {
    static let AppGroupName = "group.sh.tat.OpenCallBlock"
    /// user model
    static let UserKey = "UserKey"
}

public class DatabaseManager {
    public static let shared = DatabaseManager()
    
    /// This is shared between the app and CallDirectoryExtension
    private var storage: UserDefaults?
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()
    
    init() {
        storage = UserDefaults(suiteName: Constants.AppGroupName)
        if storage == nil {
            DDLogError("Shared storage could not be initialized!")
        }
    }
    
    /// Fetches or saves User data to shared storage
    public var user: User? {
        get {
            var user: User? = nil
            if let userData = storage?.object(forKey: Constants.UserKey) as? Data {
                do {
                    user = try decoder.decode(User.self, from: userData)
                } catch {
                    DDLogError("Could not decode User: \(error)")
                }
            }
            return user
        }
        set {
            guard let newUser = newValue else {
                storage?.removeObject(forKey: Constants.UserKey)
                storage?.synchronize()
                return
            }
            do {
                let userData = try encoder.encode(newUser)
                storage?.set(userData, forKey: Constants.UserKey)
                storage?.synchronize()
            } catch {
                DDLogError("Could not encode User: \(error)")
            }
        }
    }
}
