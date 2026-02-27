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
        var lastError: Error?

        for baseUrl in baseUrls {
            lastError = nil
            for attempt in 0...maxRetries {
                do {
                    try Task.checkCancellation()

                    let request = urlRequest(baseUrl: baseUrl)
                    let (data, response) = try await session.data(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NetworkError.invalidResponse
                    }
                    guard (200...299).contains(httpResponse.statusCode) else {
                        throw NetworkError.invalidHttpCode(httpResponse.statusCode)
                    }

                    let jsonFlags = try JSONDecoder().decode([[Tggl]].self, from: data)
                    self.setFlags(jsonFlags)
                    storage.save(flags: jsonFlags)

                    setLastError(nil)
                    markReady()

                    await scheduleNextCycleIfNeeded()
                    return

                } catch is CancellationError {
                    return
                } catch {
                    lastError = error

                    if attempt < maxRetries {
                        let delaySeconds = pow(2.0, Double(attempt))
                        do {
                            try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                        } catch {
                            return
                        }
                    }
                }
            }
        }

        if let lastError {
            setLastError(lastError)
        }

        markReady()

        await scheduleNextCycleIfNeeded()
    }

    // MARK: - Polling scheduler
    private func scheduleNextCycleIfNeeded() async {
        switch polling {
        case .enabled(let interval):
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                try Task.checkCancellation()
                fetch(trigger: .polling)
            } catch is CancellationError {
                // Cancelled while sleeping; just stop.
            } catch {
                // Unexpected error during sleep
            }
        case .disabled:
            cancelCurrentRequest()
        }
    }

    // MARK: - Request building & cancellation
    func urlRequest(baseUrl: URL) -> URLRequest {
        let requestData = try! JSONSerialization.data(withJSONObject: [self.getContext()], options: [])
        let headers = [
            "Content-Type": "application/json",
            "x-tggl-api-key": self.apiKey,
        ]

        var request = URLRequest(url: baseUrl.appendingPathComponent("typed-flags"))
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = requestData as Data
        request.timeoutInterval = self.timeoutInterval

        return request
    }

    func cancelCurrentRequest() {
        if let task = requestTask {
            task.cancel()
            requestTask = nil
        }
    }
}
