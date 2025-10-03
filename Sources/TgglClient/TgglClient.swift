import Foundation

public actor TgglClient {
    let apiKey: String
    let url: URL
    let storage: TgglStorage

    private var flags: [[Tggl]]
    var context: [String:Any?] = [:]
    var polling: Polling = .disabled
    var requestTask: Task<Void, Never>?
        
    public init(apiKey: String, url: String = "https://api.tggl.io/typed-flags") {
        self.apiKey = apiKey
        self.url = URL(string: url)!
        self.storage = TgglStorage()
        self.flags = storage.getFlags()
        self.context = storage.getContext()
    }
    
    // Encapsulated accessors for flags
    public func getFlags() -> [[Tggl]] {
        flags
    }
    
    func setFlags(_ newFlags: [[Tggl]]) {
        flags = newFlags
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
                
        fetch(trigger: .polling)
    }
    
    public func stopPolling() {
        polling = .disabled
        
        cancelCurrentRequest()
    }
    
    public func setContext(context: [String:Any]) {
        self.context = context
        
        print("setContext: \(context)")
        self.storage.save(context: context)
        
        fetch(trigger: .contextChange)
    }
}
