//
//  TgglClient+Fetch.swift
//
//
//  Created by Pierre on 04/09/2024.
//

import Foundation

extension TgglClient {
    public enum Polling {
        case disabled
        case enabled(interval: TimeInterval)
    }
    
    public enum NetworkError: Error {
        case invalidResponse
        case requestFailed(Error)
        case invalidData
        case decodingError(Error)
    }
    
    func fetch() {
        print("fetch started")
        
        cancelCurrentRequest()
        
        let completion = { [weak self] in
            guard let self = self else {
                return
            }
            
            switch polling {
            case .enabled(let interval):
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                fetch()
            case .disabled:
                requestTask = nil
            }
        }
        
        let task = Task {
                do {
                    let requestData = try! JSONSerialization.data(withJSONObject: self.context, options: [])
                    let headers = [
                        "Content-Type": "application/json",
                        "x-tggl-api-key": self.apiKey,
                    ]
                    var request = URLRequest(url: self.url)
                    request.httpMethod = "POST"
                    request.allHTTPHeaderFields = headers
                    request.httpBody = requestData as Data
                    
                    let (data, response) = try await URLSession.shared.data(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                        throw NetworkError.invalidResponse
                    }
                        
                    guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any?] else {
                        throw NetworkError.invalidData
                    }
                    
                    self.flags = json
                    
                    try await completion()

                } catch {
                    try await completion()
                    print("\(Date.now): task did error")
                }
            }
        
        self.requestTask = task
    }
    
    func cancelCurrentRequest() {
        if let task = requestTask {
            task.cancel()
            requestTask = nil
        }
    }
}
