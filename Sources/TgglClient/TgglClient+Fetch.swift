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
        case invalidHttpCode(Int)
        case requestFailed(Error)
        case invalidData
        case decodingError(Error)
    }
    
    func fetch() {
        print ("Fetch.")

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
                let (data, response) = try await URLSession.shared.data(for: urlRequest())
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw NetworkError.invalidHttpCode(httpResponse.statusCode)
                }
                      
                let json = try JSONDecoder().decode([[Tggl]].self, from: data)
                self.flags = json
                
                print("--- flags ---")
                flags.first?.forEach {
                    print("\($0.key) - \($0.value)")
                }
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
        var request = URLRequest(url: self.url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = requestData as Data
        
        return request
    }
    
    func combine() {
        print ("Combine.")
        URLSession.shared
            .dataTaskPublisher(for: urlRequest())
            .retry(1)
            .tryMap() { element -> Data in
                guard let httpResponse = element.response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    throw NetworkError.invalidResponse
                }
                return element.data
            }
            .decode(type: [[Tggl]].self, decoder: JSONDecoder())
            .sink(receiveCompletion: { print ("Received completion: \($0).") },
                  receiveValue: { user in print ("Received user: \(user).")})
    }
    
    func cancelCurrentRequest() {
        print ("Cancel request.")
        if let task = requestTask {
            task.cancel()
            requestTask = nil
        }
    }
}
