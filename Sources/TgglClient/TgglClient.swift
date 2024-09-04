import Foundation

public class TgglClient {
    let apiKey: String
    let url: URL
    var flags: [String:Any?]
    var context: [String:Any?] = [:]
    var polling: Polling = .disabled
    var requestTask: Task<Void, any Error>?
    
    public init(apiKey: String, url: String = "https://api.tggl.io/flags", flags: [String : Any?] = [:]) {
        self.apiKey = apiKey
        self.url = URL(string: url)!
        self.flags = flags
    }
    
    public func isActive(slug: String) -> Bool {
        return self.flags.keys.contains(slug)
    }
    
    public func get(slug: String, defaultValue: Any? = nil) -> Any? {
        return self.flags.keys.contains(slug) ? self.flags[slug] as Any? : defaultValue
    }
    
    public func startPolling(every interval: TimeInterval) {
        polling = .enabled(interval: interval)
                
        fetch()
    }
    
    public func stopPolling() {
        polling = .disabled
        
        cancelCurrentRequest()
    }
    
    public func setContext(context: [String:Any?]) {
        self.context = context
        
        fetch()
    }
}
