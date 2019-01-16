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

/// A protocol that provides implementation for receiving WINDOW_UPDATE frames, for those states that
/// can validly be updated.
///
/// This protocol should only be conformed to by states for the HTTP/2 connection state machine.
protocol SendingWindowUpdateState {
    var streamState: ConnectionStreamState { get set }

    var inboundFlowControlWindow: HTTP2FlowControlWindow { get set }
}

extension SendingWindowUpdateState {
    mutating func sendWindowUpdate(streamID: HTTP2StreamID, increment: UInt32) -> StateMachineResult {
        if streamID == .rootStream {
            // This is an update for the connection. We police the errors here.
            do {
                try self.inboundFlowControlWindow.windowUpdate(by: increment)
                return .succeed
            } catch let error where error is NIOHTTP2Errors.InvalidFlowControlWindowSize {
                return .connectionError(underlyingError: error, type: .flowControlError)
            } catch let error where error is NIOHTTP2Errors.InvalidWindowIncrementSize {
                return .connectionError(underlyingError: error, type: .protocolError)
            } catch {
                preconditionFailure("Unexpected error: \(error)")
            }
        } else {
            // This is an update for a specific stream: it's responsible for policing any errors.
            return self.streamState.modifyStreamState(streamID: streamID, ignoreRecentlyReset: false) {
                $0.sendWindowUpdate(windowIncrement: increment)
            }
        }
    }
}