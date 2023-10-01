import Foundation

public enum NetworkError: Error {
    case invalidResponse
    case requestFailed(Error)
    case invalidData
    case decodingError(Error)
}

public class TgglClient {
    let apiKey: String;
    let url: URL;
    var flags: [String:Any?];
    let context: [String:Any?] = [:];
    
    init(apiKey: String, url: String = "https://api.tggl.io/flags", flags: [String : Any?] = [:]) {
        self.apiKey = apiKey
        self.url = URL(string: url)!
        self.flags = flags
    }
    
    func isActive(slug: String) -> Bool {
        return self.flags.keys.contains(slug);
    }
    
    func get(slug: String, defaultValue: Any? = nil) -> Any? {
        return self.flags.keys.contains(slug) ? self.flags[slug] as Any? : defaultValue;
    }
    
    func setContext(context: [String:Any?], completionHandler: ((Error?) -> Void)? = nil) -> Void {
        let data = try! JSONSerialization.data(withJSONObject: context, options: [])
        let headers = [
            "Content-Type": "application/json",
            "x-tggl-api-key": self.apiKey,
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = data as Data

        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                completionHandler?(NetworkError.requestFailed(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                completionHandler?(NetworkError.invalidResponse)
                return
            }

            guard let data = data else {
                completionHandler?(NetworkError.invalidData)
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any?]
                self.flags = json ?? [:];
                completionHandler?(nil)
            } catch {
                completionHandler?(NetworkError.decodingError(error))
            }
        }

        task.resume()
    }
}
