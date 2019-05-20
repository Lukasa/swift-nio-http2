//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import NIO


/// A `StreamMap` is a data structure that allows storing state about streams in a
/// HTTP/2 connection.
///
/// ### Purpose
///
/// HTTP/2 connections have multiple places where they need to store per-stream state of
/// various kinds. This interface requires regular lookups of this per-stream state by
/// stream ID. This kind of lookup is performed multiple times per inbound and outbound
/// frame, which necessitates that the performance of the lookup be as rapid as possible.
/// Additionally, it is vital that this state can be modified without incurring copy-on-write
/// in the event that a CoW-able data structure is stored in this map.
///
/// A naive implementation of `StreamMap` would be backed by `Dictionary`, but in practice the
/// use of `Dictionary` has a few issues. The first is the overhead of hashing. While a
/// `HTTP2StreamID` is just a `UInt32`, it is not always possible for Swift to spot this,
/// requiring the overhead of the entire hashing API.
///
/// On top of that, the modify accessor in Dictionary is a complex one. This complexity ends
/// up defeating the Swift optimiser, leading to additional heap allocations for the coroutines,
/// as outlined in https://bugs.swift.org/browse/SR-10604.
///
/// Finally, the most common case is a relatively small number of streams in the map (no more than 10),
/// and the P90 of number of streams in the map is still only in the low hundreds. In this case, it is
/// entirely possible that the overhead of hashing is much higher than the simple cost of binary searching
/// an array.
///
/// For all these reasons we deploy this custom data structure.
///
/// ### Implementation Strategy
///
/// This data structure relies on the observation that, if one considers client and server stream IDs
/// separately, stream IDs form a naturally sorted set. That is, given that new stream IDs are required
/// to monotonically increase, if stream IDs from only one peer are always appended to a linear data
/// structure that data structure will inherently be sorted. This property continues to hold even when
/// stream ID removals on stream closure are taken into account.
///
/// It is always possible to quickly lookup an entry in a sorted linear data structure: for small data
/// structures even linear searches are fast, but for even fairly large linear data structures a binary
/// search will provide extremely quick lookup times. The speed of this lookup is likely to dwarf the cost
/// of hashing, particularly when the data structure is small.
///
/// For this reason, the backing storage of this data structure will use two separate linear data
/// structures: one for the server-initiated streams and one for the client-initiated streams.
///
/// The natural choice for a linear data structure is `Array<Value>`. However, `Array` is a poor fit for
/// stream IDs. This is because, while creation is naturally an append operation (which performs well in
/// `Array` at an amortised complexity of O(1)). Unfortunately, stream IDs are frequently *removed* from
/// the data structure as well. In `Array` this will require either reallocation of the storage to remove
/// the element, or a copy of the entire `Array` storage. Which exactly occurs is not particularly relevant:
/// what matters is that it's unavoidable for any element removal. This is less than ideal as it makes the
/// cost of removal linear in the number of elements in the storage. We'd prefer something cheaper.
///
/// The obvious choice for cheap removal is a linked list, but a useful heuristic is that the negative
/// cache properties of linked lists mean that they are rarely the right choice. While copying `Array`
/// elements is a linear-time operation, it's a *fast* one and has great cache-coherence properties. For
/// this reason, as well as the fact that lookup dominates removal in this data structure, it's probably
/// not worth burdening ourselves with a linked list.
///
/// Conveniently, NIO provides us with a better choice for this data structure, in the form of
/// `CircularBuffer<Value>`. `CircularBuffer` retains the constant time indexing and append of `Array`, while
/// giving us constant-time removal from the front and back of the data structure. Given that most streams
/// are either very long-lived (finding themselves at the front of the structure before they are removed) or
/// very short-lived (finding themselves at the back of the data structure), in many cases it will be possible
/// to achieve a constant-time removal of an element. Even when it is not possible, we incur a relatively
/// cheap compaction operation in most cases.
///
/// For this reason, we choose to use `CircularBuffer` for each of our linear data structures. The only other
/// wrinkle is in the initial sizing of these data structures. In most HTTP/2 connections the server never
/// initiates a stream. For this reason, we want to avoid allocating too much memory to serve an unlikely
/// use-case. However, in the event the server does initiate a stream we'd like to avoid having several early
/// resizing operations. For this reason, we pick a small but non-trivial initial size for the server buffer,
/// and a substantially larger one for the clients in the hope that it will avoid any need to reallocate for
/// the vast majority of connections.
internal struct StreamMap<Value: PerStreamState> {
    private var clientStreams: CircularBuffer<Value>
    private var serverStreams: CircularBuffer<Value>

    internal init() {
        self.clientStreams = CircularBuffer(initialCapacity: 64)
        self.serverStreams = CircularBuffer(initialCapacity: 8)
    }

    private init(size: Int) {
        self.clientStreams = CircularBuffer(initialCapacity: size)
        self.serverStreams = CircularBuffer(initialCapacity: size)
    }
}


/// An object conforming to `PerStreamState` holds state that specifically
/// manages state that belongs to a specific HTTP/2 stream.
internal protocol PerStreamState {
    var streamID: HTTP2StreamID { get }
}

extension StreamMap {
    static func empty() -> StreamMap {
        // TODO(cory): This still allocates.
        return StreamMap(size: 0)
    }
}


// MARK:- Modification functions.
//
// These functions all have fairly repetitive function bodies. This is unfortunate, but it is this way for a reason.
// Specifically, we need to avoid making copies of the circular buffer before we operate to avoid CoWing. This repetition
// avoids that outcome.
extension StreamMap {
    /// Insert a new value into the `StreamMap`.
    internal mutating func insert(_ value: Value) {
        if value.streamID.mayBeInitiatedBy(.client) {
            self.clientStreams.sortedAppend(value)
        } else {
            assert(self.serverStreams.first?.streamID ?? .rootStream < value.streamID)
            self.serverStreams.sortedAppend(value)
        }
    }

    /// Removes and returns the value for the given streamID.
    @discardableResult
    internal mutating func removeValue(forStreamID streamID: HTTP2StreamID) -> Value? {
        if streamID.mayBeInitiatedBy(.client) {
            return self.clientStreams.removeValue(forStreamID: streamID)
        } else {
            return self.serverStreams.removeValue(forStreamID: streamID)
        }
    }

    /// Modifies a value inline.
    ///
    /// This is a weird function. Fundamentally it has the effect of shimming the currently-underscored _modify accessor into our code,
    /// by trading the `_modify` for `@inline(__always)`. This is not necessarily a good trade, but in practice the spelling here is
    /// unlikely to change, whereas `_modify` is *highly likely* to be productised in the near term in Swift.
    ///
    /// We do try not to use `@inline(__always)`, but in the absence of stack-allocated closure contexts (which is not in Swift 5.0)
    /// there is no good option to avoid the heap-allocation for the closure context. We'll throw this away when that problem goes
    /// away, I swear!
    ///
    /// - returns: The value of the modifying closure, or `nil` if the value was not found.
    internal mutating func modifyValue<Result>(forStreamID streamID: HTTP2StreamID, _ modifyFunc: (inout Value) throws -> Result) rethrows -> Result? {
        if streamID.mayBeInitiatedBy(.client) {
            guard let index = self.clientStreams.binarySearch(needle: streamID) else {
                return nil
            }
            return try self.clientStreams.modify(index, modifyFunc)
        } else {
            guard let index = self.serverStreams.binarySearch(needle: streamID) else {
                return nil
            }
            return try self.serverStreams.modify(index, modifyFunc)
        }
    }


    struct ResultWithRemovalEffect<Result> {
        var result: Result
        var remove: Bool
    }
    internal mutating func modifyAndRemoveIfNeeded<Result>(streamID: HTTP2StreamID, _ modifyFunc: (inout Value) throws -> ResultWithRemovalEffect<Result>) rethrows -> Result? {
        if streamID.mayBeInitiatedBy(.client) {
            return try self.clientStreams.modifyAndRemoveIfNeeded(streamID: streamID, modifyFunc)
        } else {
            return try self.serverStreams.modifyAndRemoveIfNeeded(streamID: streamID, modifyFunc)
        }
    }

    internal mutating func modifyAndCreateAndRemoveIfNeeded<Result>(streamID: HTTP2StreamID, createFunc: () throws -> Value, modifyFunc: (inout Value) throws -> ResultWithRemovalEffect<Result>) rethrows -> Result? {
        if streamID.mayBeInitiatedBy(.client) {
            return try self.clientStreams.modifyAndCreateAndRemoveIfNeeded(streamID: streamID, createFunc: createFunc, modifyFunc: modifyFunc)
        } else {
            return try self.serverStreams.modifyAndCreateAndRemoveIfNeeded(streamID: streamID, createFunc: createFunc, modifyFunc: modifyFunc)
        }
    }

    /// Calls a function once with each value of the map, allowing the function
    /// to mutate the value in-place in the map.
    internal mutating func mutatingForEachValue(_ body: (inout Value) throws -> Void) rethrows {
        try self.clientStreams.mutatingForEachValue(body)
        try self.serverStreams.mutatingForEachValue(body)
    }

    internal func forEachValue(_ body: (Value) throws -> Void) rethrows {
        try self.clientStreams.forEach(body)
        try self.serverStreams.forEach(body)
    }
}


// MARK:- StreamID collections
extension StreamMap {
    struct StreamIDCollection {
        private var buffer: CircularBuffer<Value>

        fileprivate init(_ baseBuffer: CircularBuffer<Value>) {
            self.buffer = baseBuffer
        }
    }

    /// Obtains a `Collection` of `HTTP2StreamID`s stored in this `StreamMap` for the given role.
    internal func streamIDs(for role: HTTP2ConnectionStateMachine.ConnectionRole) -> StreamIDCollection {
        switch role {
        case .client:
            return StreamIDCollection(self.clientStreams)
        case .server:
            return StreamIDCollection(self.serverStreams)
        }
    }
}


extension StreamMap.StreamIDCollection: Collection {
    struct Index {
        fileprivate var baseIndex: CircularBuffer<Value>.Index
    }

    var count: Int {
        return self.buffer.count
    }

    var startIndex: Index {
        return Index(baseIndex: self.buffer.startIndex)
    }

    var endIndex: Index {
        return Index(baseIndex: self.buffer.endIndex)
    }

    subscript(position: Index) -> HTTP2StreamID {
        return self.buffer[position.baseIndex].streamID
    }

    func index(after i: Index) -> Index {
        return Index(baseIndex: self.buffer.index(after: i.baseIndex))
    }
}


extension StreamMap.StreamIDCollection.Index: Equatable {
    static func ==(lhs: StreamMap<Value>.StreamIDCollection.Index, rhs: StreamMap<Value>.StreamIDCollection.Index) -> Bool {
        return lhs.baseIndex == rhs.baseIndex
    }
}


extension StreamMap.StreamIDCollection.Index: Comparable {
    static func <(lhs: StreamMap<Value>.StreamIDCollection.Index, rhs: StreamMap<Value>.StreamIDCollection.Index) -> Bool {
        return lhs.baseIndex < rhs.baseIndex
    }

    static func >(lhs: StreamMap<Value>.StreamIDCollection.Index, rhs: StreamMap<Value>.StreamIDCollection.Index) -> Bool {
        return lhs.baseIndex > rhs.baseIndex
    }

    static func <=(lhs: StreamMap<Value>.StreamIDCollection.Index, rhs: StreamMap<Value>.StreamIDCollection.Index) -> Bool {
        return lhs.baseIndex <= rhs.baseIndex
    }

    static func >=(lhs: StreamMap<Value>.StreamIDCollection.Index, rhs: StreamMap<Value>.StreamIDCollection.Index) -> Bool {
        return lhs.baseIndex >= rhs.baseIndex
    }
}


// MARK:- Helper functions for CircularBuffer
extension CircularBuffer where Element: PerStreamState {
    /// Insert a sorted element at the end.
    ///
    /// Note that this only validates the sorting requirement in debug mode, eliding those checks in
    /// release mode.
    fileprivate mutating func sortedAppend(_ value: Element) {
        assert(self.first?.streamID ?? .rootStream < value.streamID)
        self.append(value)
    }

    /// Removes and returns an element for a given stream ID.
    @discardableResult
    fileprivate mutating func removeValue(forStreamID streamID: HTTP2StreamID) -> Element? {
        guard let index = self.binarySearch(needle: streamID) else {
            return nil
        }
        return self.remove(at: index)
    }

    fileprivate mutating func modifyValue<Result>(forStreamID streamID: HTTP2StreamID, _ modifyFunc: (inout Element) throws -> Result) rethrows -> Result? {
        guard let index = self.binarySearch(needle: streamID) else {
            return nil
        }
        return try self.modify(index, modifyFunc)
    }

    fileprivate mutating func modifyAndRemoveIfNeeded<Result>(streamID: HTTP2StreamID, _ modifyFunc: (inout Element) throws -> StreamMap<Element>.ResultWithRemovalEffect<Result>) rethrows -> Result? {
        guard let index = self.binarySearch(needle: streamID) else {
            return nil
        }
        let result = try self.modify(index, modifyFunc)
        if result.remove {
            self.remove(at: index)
        }
        return result.result
    }

    fileprivate mutating func modifyAndCreateAndRemoveIfNeeded<Result>(streamID: HTTP2StreamID, createFunc: () throws -> Element, modifyFunc: (inout Element) throws -> StreamMap<Element>.ResultWithRemovalEffect<Result>) rethrows -> Result? {
        if let index = self.binarySearch(needle: streamID) {
            let result = try self.modify(index, modifyFunc)
            if result.remove {
                self.remove(at: index)
            }
            return result.result
        } else {
            var newValue = try createFunc()
            let result = try modifyFunc(&newValue)
            if !result.remove {
                // Here we invert the logic: if we aren't removing, we must keep it.
                self.sortedAppend(newValue)
            }
            return result.result
        }
    }

    fileprivate mutating func mutatingForEachValue(_ body: (inout Element) throws -> Void) rethrows {
        var index = self.startIndex
        while index != self.endIndex {
            try self.modify(index, body)
            self.formIndex(after: &index)
        }
    }

    /// A straightforward implementation of binary search.
    ///
    /// This function is a bit unnecessarily specific, due to the fact that `PerStreamState` is a bit
    /// unnecessarily specific. In principle this can all be generalised to a data structure with a
    /// key that conforms to `Comparable`. However, we're unlikely to ever need this for a different use-case,
    /// so the unnecessary specificity can stay. If we do need it we can re-evaluate in the future.
    ///
    /// Note that this function does not validate that the buffer is sorted, and only works if it is!
    fileprivate func binarySearch(needle: HTTP2StreamID) -> Index? {
        var bottomIndex = self.startIndex
        var topIndex = self.endIndex
        var sliceSize = self.distance(from: bottomIndex, to: topIndex)

        while sliceSize > 0 {
            let middleIndex = self.index(bottomIndex, offsetBy: sliceSize / 2)

            switch self[middleIndex].streamID {
            case let potentialKey where potentialKey > needle:
                // Too big. We want to search everything smaller than here.
                topIndex = middleIndex
            case let potentialKey where potentialKey < needle:
                // Too small. We want to search everything larger than here.
                bottomIndex = self.index(after: middleIndex)
            case let potentialKey:
                // Got an answer!
                assert(potentialKey == needle)
                return middleIndex
            }

            sliceSize = self.distance(from: bottomIndex, to: topIndex)
        }

        return nil
    }
}


// MARK:- Conformances

extension HTTP2StreamStateMachine: PerStreamState { }
