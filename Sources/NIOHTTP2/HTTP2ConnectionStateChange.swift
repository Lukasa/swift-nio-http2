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

/// An `NIOHTTP2ConnectionStateChange` provides information about the state change
/// that occurred as a result of a single frame being sent or received.
///
/// This enumeration allows users to avoid needing to replicate the complete HTTP/2
/// state machine. Instead, users can use this enumeration to determine the new state
/// of the connection and affected streams.
public enum NIOHTTP2ConnectionStateChange: Hashable {
    /// A stream has been created.
    case streamCreated(StreamCreated)

    /// A stream has been closed.
    case streamClosed(StreamClosed)

    /// A stream was created and then immediately closed. This can happen when a stream reserved
    /// via PUSH_PROMISE has a HEADERS frame with END_STREAM sent on it by the server.
    case streamCreatedAndClosed(StreamCreatedAndClosed)

    /// A frame was sent or received that changes some flow control windows.
    case flowControlChange(FlowControlChange)

    /// Multiple streams have been closed. This happens as a result of a GOAWAY frame
    /// being sent or received.
    case bulkStreamClosure(BulkStreamClosure)

    /// Settings have been changed.
    case settingsChanged(SettingsChanged)

    /// A stream has been created.
    public struct StreamCreated: Hashable {
        public var streamID: HTTP2StreamID

        /// The initial local stream window size. This may be nil if there is no local stream window.
        /// This occurs if the stream has been pushed by the remote peer, in which case we will never be able
        /// to send on it.
        public var localStreamWindowSize: Int?

        /// The initial remote stream window size. This may be nil if there is no remote stream window.
        /// This occurs if the stream has been pushed by the local peer, in which case tje remote peer will never be able
        /// to send on it.
        public var remoteStreamWindowSize: Int?

        public init(streamID: HTTP2StreamID, localStreamWindowSize: Int?, remoteStreamWindowSize: Int?) {
            self.streamID = streamID
            self.localStreamWindowSize = localStreamWindowSize
            self.remoteStreamWindowSize = remoteStreamWindowSize
        }
    }

    /// A stream has been closed.
    public struct StreamClosed: Hashable {
        public var streamID: HTTP2StreamID

        public var localConnectionWindowSize: Int

        public var remoteConnectionWindowSize: Int

        public var reason: HTTP2ErrorCode?

        public init(streamID: HTTP2StreamID, localConnectionWindowSize: Int, remoteConnectionWindowSize: Int, reason: HTTP2ErrorCode?) {
            self.streamID = streamID
            self.localConnectionWindowSize = localConnectionWindowSize
            self.remoteConnectionWindowSize = remoteConnectionWindowSize
            self.reason = reason
        }
    }

    /// A stream has been created and immediately closed. In this case, the only relevant bit of information
    /// is the stream ID: flow control windows are not relevant as this frame is not flow controlled and does
    /// not change window sizes.
    public struct StreamCreatedAndClosed: Hashable {
        public var streamID: HTTP2StreamID

        public init(streamID: HTTP2StreamID) {
            self.streamID = streamID
        }
    }

    /// A flow control window has changed.
    ///
    /// A change to a flow control window may affect the connection window and optionally
    /// may also affect a stream window. This occurs due to the sending or receiving of
    /// a flow controlled frame or a window update frame. Flow controlled frames change
    /// both the connection and stream window sizes: window update frames change
    /// only one. To avoid ambiguity, we report the current window size of the connection
    /// on all such events, and the relevant stream if there is one (which there usually is).
    public struct FlowControlChange: Hashable {
        public var localConnectionWindowSize: Int

        public var remoteConnectionWindowSize: Int

        public var localStreamWindowSize: StreamWindowSizeChange?

        /// The information about the stream window size. Either the local or remote
        /// stream window information may be nil, if there is no flow control window
        /// for that direction (e.g. if the stream is half-closed).
        public struct StreamWindowSizeChange: Hashable {
            public var streamID: HTTP2StreamID

            public var localStreamWindowSize: Int?

            public var remoteStreamWindowSize: Int?

            public init(streamID: HTTP2StreamID, localStreamWindowSize: Int?, remoteStreamWindowSize: Int?) {
                self.streamID = streamID
                self.localStreamWindowSize = localStreamWindowSize
                self.remoteStreamWindowSize = remoteStreamWindowSize
            }
        }

        public init(localConnectionWindowSize: Int, remoteConnectionWindowSize: Int, localStreamWindowSize: StreamWindowSizeChange?) {
            self.localConnectionWindowSize = localConnectionWindowSize
            self.remoteConnectionWindowSize = remoteConnectionWindowSize
            self.localStreamWindowSize = localStreamWindowSize
        }
    }

    /// A large number of streams have been closed at once.
    public struct BulkStreamClosure: Hashable {
        public var closedStreams: [HTTP2StreamID]

        public init(closedStreams: [HTTP2StreamID]) {
            self.closedStreams = closedStreams
        }
    }

    /// Settings have changed in a way that is not trivial to decode.
    ///
    /// This object keeps track of the change on all stream window sizes via
    /// SETTINGS frame.
    public struct SettingsChanged: Hashable {
        public var streamWindowSizeChange: Int

        public init(streamWindowSizeChange: Int) {
            self.streamWindowSizeChange = streamWindowSizeChange
        }
    }
}


/// A representation of a state change at the level of a single stream.
///
/// While the NIOHTTP2ConnectionStateChange is an object that affects an entire connection,
/// it is more accurately the composition of an effect on a single stream and a wider effect on a
/// connection. This object encapsulates the effect on a single stream, and can be used along with
/// other information to bootstrap a NIOHTTP2ConnectionStateChange.
///
/// Where possible, this object uses the structures from NIOHTTP2ConnectionStateChange. Where not possible
/// it defines its own.
internal enum StreamStateChange: Hashable {
    case streamCreated(NIOHTTP2ConnectionStateChange.StreamCreated)

    case streamClosed(StreamClosed)

    case windowSizeChange(NIOHTTP2ConnectionStateChange.FlowControlChange.StreamWindowSizeChange)

    case streamCreatedAndClosed(NIOHTTP2ConnectionStateChange.StreamCreatedAndClosed)

    struct StreamClosed: Hashable {
        var streamID: HTTP2StreamID

        var reason: HTTP2ErrorCode?
    }
}


internal extension NIOHTTP2ConnectionStateChange {
    init<ConnectionState: HasFlowControlWindows>(_ streamChange: StreamStateChange, connectionState: ConnectionState) {
        switch streamChange {
        case .streamClosed(let streamClosedState):
            self = .streamClosed(.init(streamID: streamClosedState.streamID,
                                       localConnectionWindowSize: Int(connectionState.outboundFlowControlWindow),
                                       remoteConnectionWindowSize: Int(connectionState.inboundFlowControlWindow),
                                       reason: streamClosedState.reason))
        case .streamCreated(let streamCreated):
            self = .streamCreated(streamCreated)
        case .streamCreatedAndClosed(let streamCreatedAndClosed):
            self = .streamCreatedAndClosed(streamCreatedAndClosed)
        case .windowSizeChange(let streamSizeChange):
            self = .flowControlChange(.init(localConnectionWindowSize: Int(connectionState.outboundFlowControlWindow),
                                            remoteConnectionWindowSize: Int(connectionState.inboundFlowControlWindow),
                                            localStreamWindowSize: streamSizeChange))
        }
    }
}
