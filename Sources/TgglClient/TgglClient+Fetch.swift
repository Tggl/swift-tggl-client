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
        print("Fetch: \(trigger)")
        
        // If this is a context-driven refresh, cancel any in-flight request first
        if case .contextChange = trigger {
            cancelCurrentRequest()
        }
        
        let task = Task { [weak self] in
            guard let self = self else { return }
            await self._fetchBody(trigger: trigger)
        }
        
        self.requestTask = task
    }
    
    // MARK: - Internal fetch body (actor-isolated)
    private func _fetchBody(trigger: FetchTrigger) async {
        do {
            let request = urlRequest()
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw NetworkError.invalidHttpCode(httpResponse.statusCode)
            }
            
            print("Data received: \(String(data: data, encoding: .utf8) ?? "(no data)")")
            
            let jsonFlags = try JSONDecoder().decode([[Tggl]].self, from: data)
            self.setFlags(jsonFlags)
            storage.save(flags: jsonFlags)
            
            let currentFlags = getFlags()
            print("--- flags (\(String(describing: currentFlags.first?.count)) ---")
            currentFlags.first?.forEach {
                print("\($0.key) - \($0.value)")
            }
            print("flags: \(currentFlags)")
            print("-------------")
            
        } catch is CancellationError {
            // Task was cancelled (either by stopPolling or a context change).
            print("\(Date.now): fetch cancelled")
            return
        } catch {
            print("\(Date.now): task did error \(error)")
        }
        
        // Schedule the next polling cycle if enabled
        await scheduleNextCycleIfNeeded()
    }
    
    // MARK: - Polling scheduler
    private func scheduleNextCycleIfNeeded() async {
        switch polling {
        case .enabled(let interval):
            do {
                // Sleep cooperates with cancellation
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                try Task.checkCancellation()
                fetch(trigger: .polling)
            } catch is CancellationError {
                // Cancelled while sleeping; just stop.
                print("\(Date.now): polling sleep cancelled")
            } catch {
                print("\(Date.now): polling sleep error \(error)")
            }
        case .disabled:
            // Ensure we don't keep a finished task around
            cancelCurrentRequest()
        }
    }
    
    // MARK: - Request building & cancellation (actor-isolated)
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
