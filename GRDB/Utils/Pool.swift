import Dispatch

/// A Pool maintains a set of elements that are built them on demand. A pool has
/// a maximum number of elements.
///
///     // A pool of 3 integers
///     var number = 0
///     let pool = Pool<Int>(maximumCount: 3, makeElement: {
///         number = number + 1
///         return number
///     })
///
/// The function get() dequeues an available element and gives this element to
/// the block argument. During the block execution, the element is not
/// available. When the block is ended, the element is available again.
///
///     // got 1
///     pool.get { n in
///         print("got \(n)")
///     }
///
/// If there is no available element, the pool builds a new element, unless the
/// maximum number of elements is reached. In this case, the get() method
/// blocks the current thread, until an element eventually turns available again.
///
///     DispatchQueue.concurrentPerform(iterations: 6) { _ in
///         pool.get { n in
///             print("got \(n)")
///         }
///     }
///
///     got 1
///     got 2
///     got 3
///     got 2
///     got 1
///     got 3
final class Pool<T: Sendable>: Sendable {
    private class Item: @unchecked Sendable {
        // @unchecked Sendable because `isAvailable` is protected by `contentLock`.
        let element: T
        var isAvailable: Bool
        
        init(element: T, isAvailable: Bool) {
            self.element = element
            self.isAvailable = isAvailable
        }
    }
    
    private struct Content {
        var items: [Item]
        
        /// The number of created items. May become greater than the number
        /// of elements in items, as some items are destroyed and other
        /// are created.
        var createdCount = 0
    }
    
    typealias ElementAndRelease = (element: T, release: @Sendable (PoolCompletion) -> Void)
    
    private let makeElement: @Sendable (Int) throws -> T
    private let contentLock = ReadWriteLock(Content(items: [], createdCount: 0))
    private let itemsSemaphore: DispatchSemaphore // limits the number of elements
    private let itemsGroup: DispatchGroup         // knows when no element is used
    private let barrierQueue: DispatchQueue
    private let barrierActor: DispatchQueueActor
    private let semaphoreWaitingQueue: DispatchQueue // Inspired by https://khanlou.com/2016/04/the-GCD-handbook/
    private let semaphoreWaitingActor: DispatchQueueActor
    
    /// Creates a Pool.
    ///
    /// - parameters:
    ///     - maximumCount: The maximum number of elements.
    ///     - qos: The quality of service of asynchronous accesses.
    ///     - makeElement: A function that creates an element. It is called
    ///       on demand. Its argument is the index of the created elements
    ///       (1, then 2, etc).
    init(
        maximumCount: Int,
        qos: DispatchQoS = .unspecified,
        makeElement: @escaping @Sendable (_ index: Int) throws -> T)
    {
        GRDBPrecondition(maximumCount > 0, "Pool size must be at least 1")
        self.makeElement = makeElement
        self.itemsSemaphore = DispatchSemaphore(value: maximumCount)
        self.itemsGroup = DispatchGroup()
        self.barrierQueue = DispatchQueue(label: "GRDB.Pool.barrier", qos: qos, attributes: [.concurrent])
        self.barrierActor = DispatchQueueActor(queue: barrierQueue, flags: [.barrier])
        self.semaphoreWaitingQueue = DispatchQueue(label: "GRDB.Pool.wait", qos: qos)
        self.semaphoreWaitingActor = DispatchQueueActor(queue: semaphoreWaitingQueue)
    }
    
    /// Returns a tuple (element, release)
    /// Client must call release(), only once, after the element has been used.
    func get() throws -> ElementAndRelease {
        try barrierQueue.sync {
            itemsSemaphore.wait()
            itemsGroup.enter()
            do {
                let item = try contentLock.withLock { content -> Item in
                    if let item = content.items.first(where: \.isAvailable) {
                        item.isAvailable = false
                        return item
                    } else {
                        content.createdCount += 1
                        let element = try makeElement(content.createdCount)
                        let item = Item(element: element, isAvailable: false)
                        content.items.append(item)
                        return item
                    }
                }
                return (element: item.element, release: { self.release(item, completion: $0) })
            } catch {
                itemsSemaphore.signal()
                itemsGroup.leave()
                throw error
            }
        }
    }
    
    /// Returns a tuple (element, release)
    /// Client must call release(), only once, after the element has been used.
    func get() async throws -> ElementAndRelease {
        // See asyncGet(_:)
        try await semaphoreWaitingActor.execute {
            try self.get()
        }
    }
    
    /// Eventually produces a tuple (element, release), where element is
    /// intended to be used asynchronously.
    ///
    /// Client must call release(), only once, after the element has been used.
    ///
    /// - important: The `execute` argument is executed in a serial dispatch
    ///   queue, so make sure you use the element asynchronously.
    func asyncGet(_ execute: @escaping @Sendable (Result<ElementAndRelease, Error>) -> Void) {
        // Inspired by https://khanlou.com/2016/04/the-GCD-handbook/
        // > We wait on the semaphore in the serial queue, which means that
        // > we’ll have at most one blocked thread when we reach maximum
        // > executing blocks on the concurrent queue. Any other tasks the user
        // > enqueues will sit inertly on the serial queue waiting to be
        // > executed, and won’t cause new threads to be started.
        semaphoreWaitingQueue.async {
            execute(Result { try self.get() })
        }
    }
    
    /// Performs a synchronous block with an element. The element turns
    /// available after the block has executed.
    func get<U>(block: (T) throws -> U) throws -> U {
        let (element, completion) = try get()
        defer { completion(.reuse) }
        return try block(element)
    }
    
    /// Performs an asynchronous block with an element. The element turns
    /// available after the block has executed.
    func get<U>(block: (T) async throws -> U) async throws -> U {
        let (element, completion) = try await get()
        defer { completion(.reuse) }
        return try await block(element)
    }
    
    private func release(_ item: Item, completion: PoolCompletion) {
        contentLock.withLock { content in
            switch completion {
            case .reuse:
                // This is why Item is a class, not a struct: so that we can
                // release it without having to find in it the items array.
                item.isAvailable = true
            case .discard:
                // Discard should be rare: perform lookup.
                if let index = content.items.firstIndex(where: { $0 === item }) {
                    content.items.remove(at: index)
                }
            }
        }
        itemsSemaphore.signal()
        itemsGroup.leave()
    }
    
    /// Performs a block on each pool element, available or not.
    /// The block is run is some arbitrary dispatch queue.
    func forEach(_ body: (T) throws -> Void) rethrows {
        try contentLock.read { content in
            for item in content.items {
                try body(item.element)
            }
        }
    }
    
    /// Removes all elements from the pool.
    /// Currently used elements won't be reused.
    func removeAll() {
        contentLock.withLock { $0.items.removeAll() }
    }
    
    /// Blocks until no element is used, and runs the `barrier` function before
    /// any other element is dequeued.
    func barrier<R>(execute barrier: () throws -> R) rethrows -> R {
        try barrierQueue.sync(flags: [.barrier]) {
            itemsGroup.wait()
            return try barrier()
        }
    }
    
    func barrier<R: Sendable>(
        execute barrier: sending () throws -> sending R
    ) async rethrows -> sending R {
        try await barrierActor.execute {
            itemsGroup.wait()
            return try barrier()
        }
    }
    
    /// Asynchronously runs the `barrier` function when no element is used, and
    /// before any other element is dequeued.
    func asyncBarrier(execute barrier: @escaping @Sendable () -> Void) {
        barrierQueue.async(flags: [.barrier]) {
            self.itemsGroup.wait()
            barrier()
        }
    }
}

enum PoolCompletion {
    // Reuse the element
    case reuse
    // Discard the element
    case discard
}
