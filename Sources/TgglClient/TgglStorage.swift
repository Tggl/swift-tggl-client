//
//  TgglStorage.swift
//  TgglClient
//
//  Created by Pierre on 15/09/2025.
//

import Foundation

public struct TgglStorage {
    
    private let defaults = UserDefaults(suiteName: "tggl")
    
    private let contextKey: String = "context"
    private let flagsKey: String = "flags"

    // context
    func save(context: [String: Any]) {
        defaults?.set(context, forKey: contextKey)
    }
    
    func getContext() -> [String: Any] {
        return defaults?.array(forKey: contextKey) as? [String: Any] ?? [:]
    }
    
    // flags
    func save(flags: [[Tggl]]) {
        if let data = try? JSONEncoder().encode(flags) {
            defaults?.set(data, forKey: flagsKey)
        }
    }
    
    func getFlags() -> [[Tggl]] {
        if let data = defaults?.data(forKey: flagsKey),
           let decoded = try? JSONDecoder().decode([[Tggl]].self, from: data) {
            return decoded
        }
        return []
    }
}
