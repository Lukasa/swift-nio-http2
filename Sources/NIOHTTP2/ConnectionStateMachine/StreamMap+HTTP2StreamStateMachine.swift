//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

internal extension StreamMap where Value == HTTP2StreamStateMachine {
    /// Transform the value of an optional HTTP2StreamStateMachine, setting it to nil
    /// if the result of the transformation is to close the stream.
    ///
    /// - parameters:
    ///     - modifier: A block that will modify the contained value in the
    ///         optional, if there is one present.
    /// - returns: The return value of the block or `nil` if the optional was `nil`.
    mutating func autoClosingTransform<T>(streamID: HTTP2StreamID, _ modifier: (inout Value) throws -> T) rethrows -> T? {
        return try self.modifyAndRemoveIfNeeded(streamID: streamID) { value in
            let innerResult = try modifier(&value)

            switch value.closed {
            case .notClosed:
                return .init(result: innerResult, remove: false)
            case .closed:
                return .init(result: innerResult, remove: true)
            }
        }
    }


    // This function exists as a performance optimisation: by mutating the optional returned from Dictionary directly
    // inline, we can avoid the dictionary needing to hash the key twice, which it would have to do if we removed the
    // value, mutated it, and then re-inserted it.
    //
    // However, we need to be a bit careful here, as the performance gain from doing this would be completely swamped
    // if the Swift compiler failed to inline this method into its caller. This would force these closures to have their
    // contexts heap-allocated, and the cost of doing that is vastly higher than the cost of hashing the key a second
    // time. So for this reason we make it clear to the compiler that this method *must* be inlined at the call-site.
    // Sorry about doing this!
    @inline(__always)
    mutating func transformOrCreateAutoClose<T>(streamID: HTTP2StreamID, _ creator: () throws -> Value, _ transformer: (inout Value) -> T) rethrows -> T? {
        return try self.modifyAndCreateAndRemoveIfNeeded(streamID: streamID, createFunc: creator) { value in
            let innerResult = transformer(&value)

            switch value.closed {
            case .notClosed:
                return .init(result: innerResult, remove: false)
            case .closed:
                return .init(result: innerResult, remove: true)
            }
        }
    }
}
