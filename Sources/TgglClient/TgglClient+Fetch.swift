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
    
    public enum FetchTrigger {
        case polling
        case contextChange
    }
    
    public enum NetworkError: Error {
        case invalidResponse
        case invalidHttpCode(Int)
        case invalidData
    }
    
    func fetch(trigger: FetchTrigger) {
        print ("Fetch: \(trigger)")
        cancelCurrentRequest()
        
        let completion = { [weak self] in
            guard let self = self else {
                return
            }
            
            switch await polling {
            case .enabled(let interval):
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await fetch(trigger: .polling)
            case .disabled:
                await cancelCurrentRequest()
            }
        }
        
        let task = Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: urlRequest())
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw NetworkError.invalidHttpCode(httpResponse.statusCode)
                }
                
                print("Data received: \(String(data: data, encoding: .utf8) ?? "(no data)")")
                      
                let jsonFlags = try JSONDecoder().decode([[Tggl]].self, from: data)
                self.flags = jsonFlags
                storage.save(flags: jsonFlags)
                
                print("--- flags (\(String(describing: flags.first?.count)) ---")
                flags.first?.forEach {
                    print("\($0.key) - \($0.value)")
                }
                
                print("flags: \(flags)")
                
                print("-------------")

            } catch {
                print("\(Date.now): task did error \(error)")
            }
        
            try await completion()

        }
        
        self.requestTask = task
    }
    
    func urlRequest() -> URLRequest {
        let requestData = try! JSONSerialization.data(withJSONObject: [self.context], options: [])
        let headers = [
            "Content-Type": "application/json",
            "x-tggl-api-key": self.apiKey,
        ]
        
        print("request data: \(String(data: requestData, encoding: .utf8) ?? "(no data)")")
        var request = URLRequest(url: self.url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = requestData as Data
        
        return request
    }
    
    func cancelCurrentRequest() {
        if let task = requestTask {
            task.cancel()
            requestTask = nil
        }
    }
}
