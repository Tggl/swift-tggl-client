import Foundation
import Combine

public actor TgglClient: ObservableObject {
    let apiKey: String
    let url: URL
    let storage: TgglStorage

    @Published private var flags: [[Tggl]] = []

    private var context: [String:Any] = [:]
    var polling: Polling = .disabled
    var requestTask: Task<Void, Never>?
        
    public init(apiKey: String, url: String = "https://api.tggl.io/typed-flags") {
        self.apiKey = apiKey
        self.url = URL(string: url)!
        self.storage = TgglStorage()
        
        Task { [weak self] in
            guard let self else { return }
            
            let initialFlags = await storage.getFlags()
            await setFlags(initialFlags)
            
            let initialContext = await storage.getContext()
            await setContext(context: initialContext)
        }
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
    
    public func getSlugPublisher(slug: String) -> AnyPublisher<Tggl, Never> {
        $flags
            .compactMap({ tggl in
                guard let flags = tggl.first else { return nil }
                guard let flag = flags.first(where: { $0.key == slug }) else { return nil }
                return flag
            })
            .removeDuplicates(by: { $0.value == $1.value })
            .eraseToAnyPublisher()
    }
    
    public func getContext() -> [String:Any] {
        context
    }
    
    public func setContext(context: [String:Any]) {
        self.context = context
        
        print("setContext: \(context)")
        self.storage.save(context: context)
        
        fetch(trigger: .contextChange)
    }
}
