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
//
// HTTP2FrameParserTests+XCTest.swift
//
import XCTest

///
/// NOTE: This file was generated by generate_linux_tests.rb
///
/// Do NOT edit this file directly as it will be regenerated automatically when needed.
///

extension HTTP2FrameParserTests {

   static var allTests : [(String, (HTTP2FrameParserTests) -> () throws -> Void)] {
      return [
                ("testDataFrameDecodingNoPadding", testDataFrameDecodingNoPadding),
                ("testDataFrameDecodingWithPadding", testDataFrameDecodingWithPadding),
                ("testDataFrameEncoding", testDataFrameEncoding),
                ("testDataFrameDecodeFailureRootStream", testDataFrameDecodeFailureRootStream),
                ("testDataFrameDecodeFailureExcessPadding", testDataFrameDecodeFailureExcessPadding),
                ("testHeadersFrameDecodingNoPriorityNoPadding", testHeadersFrameDecodingNoPriorityNoPadding),
                ("testHeadersFrameDecodingNoPriorityWithPadding", testHeadersFrameDecodingNoPriorityWithPadding),
                ("testHeadersFrameDecodingWithPriorityNoPadding", testHeadersFrameDecodingWithPriorityNoPadding),
                ("testHeadersFrameDecodingWithPriorityWithPadding", testHeadersFrameDecodingWithPriorityWithPadding),
                ("testHeadersFrameDecodeFailures", testHeadersFrameDecodeFailures),
                ("testHeadersFrameEncodingNoPriority", testHeadersFrameEncodingNoPriority),
                ("testHeadersFrameEncodingWithPriority", testHeadersFrameEncodingWithPriority),
                ("testPriorityFrameDecoding", testPriorityFrameDecoding),
                ("testPriorityFrameDecodingFailure", testPriorityFrameDecodingFailure),
                ("testPriorityFrameEncoding", testPriorityFrameEncoding),
                ("testResetStreamFrameDecoding", testResetStreamFrameDecoding),
                ("testResetStreamFrameDecodingFailure", testResetStreamFrameDecodingFailure),
                ("testResetStreamFrameEncoding", testResetStreamFrameEncoding),
                ("testSettingsFrameDecoding", testSettingsFrameDecoding),
                ("testSettingsFrameDecodingWithUnknownItems", testSettingsFrameDecodingWithUnknownItems),
                ("testSettingsFrameDecodingFailure", testSettingsFrameDecodingFailure),
                ("testSettingsFrameEncoding", testSettingsFrameEncoding),
                ("testSettingsAckFrameDecoding", testSettingsAckFrameDecoding),
                ("testSettingsAckFrameDecodingFailure", testSettingsAckFrameDecodingFailure),
                ("testSettingsAckFrameEncoding", testSettingsAckFrameEncoding),
                ("testPushPromiseFrameDecodingNoPadding", testPushPromiseFrameDecodingNoPadding),
                ("testPushPromiseFrameDecodingWithPadding", testPushPromiseFrameDecodingWithPadding),
                ("testPushPromiseFrameDecodingFailure", testPushPromiseFrameDecodingFailure),
                ("testPushPromiseFrameEncoding", testPushPromiseFrameEncoding),
                ("testPingFrameDecoding", testPingFrameDecoding),
                ("testPingAckFrameDecoding", testPingAckFrameDecoding),
                ("testPingFrameDecodingFailure", testPingFrameDecodingFailure),
                ("testPingFrameEncoding", testPingFrameEncoding),
                ("testPingAckFrameEncoding", testPingAckFrameEncoding),
                ("testGoAwayFrameDecoding", testGoAwayFrameDecoding),
                ("testGoAwayFrameDecodingFailure", testGoAwayFrameDecodingFailure),
                ("testGoAwayFrameEncodingWithOpaqueData", testGoAwayFrameEncodingWithOpaqueData),
                ("testGoAwayFrameEncodingWithNoOpaqueData", testGoAwayFrameEncodingWithNoOpaqueData),
                ("testWindowUpdateFrameDecoding", testWindowUpdateFrameDecoding),
                ("testWindowUpdateFrameDecodingFailure", testWindowUpdateFrameDecodingFailure),
                ("testWindowUpdateFrameEncoding", testWindowUpdateFrameEncoding),
                ("testContinuationFrameDecoding", testContinuationFrameDecoding),
           ]
   }
}

