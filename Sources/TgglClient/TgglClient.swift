import Foundation

public class TgglClient {
    let apiKey: String
    let url: URL
    var flags: [[Tggl]]
    var context: [String:Any?] = [:]
    var polling: Polling = .disabled
    var requestTask: Task<Void, any Error>?
    
    public init(apiKey: String, url: String = "https://api.tggl.io/typed-flags", flags: [[Tggl]] = []) {
        self.apiKey = apiKey
        self.url = URL(string: url)!
        self.flags = flags
    }
    
    public func isActive(slug: String) -> Bool {
        return self.flags.first?.contains { tggl in
            tggl.key == slug
        } ?? false
    }
    
    public func get(slug: String, defaultValue: Tggl? = nil) -> Tggl? {
        return self.flags.first?.first(where: { tggl in
            tggl.key == slug
        })
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
