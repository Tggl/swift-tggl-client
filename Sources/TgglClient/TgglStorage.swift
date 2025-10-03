//
//  TgglStorage.swift
//  TgglClient
//
//  Created by Pierre on 15/09/2025.
//

import Foundation

struct TgglStorage {
    
    private let defaults: UserDefaults = UserDefaults(suiteName: "tggl") ?? .standard
    
    private let contextKey: String = "context"
    private let flagsKey: String = "flags"

    // context
    func save(context: [String: Any]) {
        // Only property-list-compatible values will be stored.
        defaults.set(context, forKey: contextKey)
    }
    
    func getContext() -> [String: Any] {
        defaults.dictionary(forKey: contextKey) ?? [:]
    }
    
    // flags
    func save(flags: [[Tggl]]) {
        if let data = try? JSONEncoder().encode(flags) {
            defaults.set(data, forKey: flagsKey)
        }
    }
    
    func getFlags() -> [[Tggl]] {
        if let data = defaults.data(forKey: flagsKey),
           let decoded = try? JSONDecoder().decode([[Tggl]].self, from: data) {
            return decoded
        }
        return []
    }
    
    // convenience for tests or full reset
    func clear() {
        defaults.removeObject(forKey: contextKey)
        defaults.removeObject(forKey: flagsKey)
    }
}
