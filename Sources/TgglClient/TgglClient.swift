import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

public actor TgglClient: ObservableObject {
     let apiKey: String
     let url: URL
     let storage: TgglStorage
     let session: URLSession

    @Published private var flags: [[Tggl]] = []

    private var context: [String:Any] = [:]
    var polling: Polling = .disabled
    var requestTask: Task<Void, Never>?
        
    public init(apiKey: String, url: String = "https://api.tggl.io/typed-flags", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.url = URL(string: url)!
        self.storage = TgglStorage()
        self.session = session
        
        Task { [weak self] in
            guard let self else { return }
            
            let initialFlags = await storage.getFlags()
            await setFlags(initialFlags)
            
            let initialContext = await storage.getContext()
            await setContext(context: initialContext)
        }

        self.subscribeToAppStateNotifications()
    }
    
    // Encapsulated accessors for flags
    public func getFlags() -> [Tggl] {
        flags.first ?? []
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
    
    public func publisher(for flag: String) -> AnyPublisher<Tggl, Never> {
        $flags
            .compactMap({ tggl in
                guard let flags = tggl.first else { return nil }
                guard let flag = flags.first(where: { $0.key == flag }) else { return nil }
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

extension TgglClient {
    func subscribeToAppStateNotifications() {
        // Observe app lifecycle (iOS only)
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil,queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                if polling == .enabled(interval: _) {
                    cancelCurrentRequest()
                }
            }
        }
        
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                if polling == .enabled(interval: _) {
                    fetch(fetch(trigger: .polling))
                }
            }
        }
        #endif
    }
}
