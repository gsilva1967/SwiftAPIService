//
//  SSETests.swift
//  SwiftAPIServiceTests
//

import Foundation
import Testing
@testable import SwiftAPICore

@Test func sseParserParsesEventFields() throws {
    var parser = SSEParser()

    #expect(try parser.consume(line: "id: 42") == nil)
    #expect(try parser.consume(line: "event: message") == nil)
    #expect(try parser.consume(line: "data: hello") == nil)
    #expect(try parser.consume(line: "retry: 1500") == nil)

    let parsedEvent = try parser.consume(line: "")
    let event = try #require(parsedEvent)
    #expect(event.id == "42")
    #expect(event.event == "message")
    #expect(event.data == "hello")
    #expect(event.retry == 1500)
}

@Test func sseParserSupportsMultilineDataAndComments() throws {
    var parser = SSEParser()

    #expect(try parser.consume(line: ": this is a comment") == nil)
    #expect(try parser.consume(line: "data: first line") == nil)
    #expect(try parser.consume(line: "data: second line") == nil)

    let parsedEvent = try parser.consume(line: "")
    let event = try #require(parsedEvent)
    #expect(event.data == "first line\nsecond line")
}

@Test func sseParserThrowsOnInvalidRetryValue() {
    var parser = SSEParser()
    #expect(throws: SSEError.self) {
        try parser.consume(line: "retry: abc")
    }
}

@Test func sseRetryStrategyUsesServerRetryWhenPresent() {
    let strategy = SSERetryStrategy(
        baseDelayMilliseconds: 1_000,
        maxDelayMilliseconds: 30_000,
        maxAttempts: nil,
        jitterRatio: 0
    )

    let delayNs = strategy.nextDelayNanoseconds(attempt: 3, serverRetryMilliseconds: 2_500)
    #expect(delayNs == 2_500_000_000)
}

@Test func sseRetryStrategyBackoffAndAttemptLimit() {
    let strategy = SSERetryStrategy(
        baseDelayMilliseconds: 500,
        maxDelayMilliseconds: 10_000,
        maxAttempts: 2,
        jitterRatio: 0
    )

    #expect(strategy.canRetry(attempt: 0) == true)
    #expect(strategy.canRetry(attempt: 1) == true)
    #expect(strategy.canRetry(attempt: 2) == false)

    let delay0 = strategy.nextDelayNanoseconds(attempt: 0, serverRetryMilliseconds: nil)
    let delay1 = strategy.nextDelayNanoseconds(attempt: 1, serverRetryMilliseconds: nil)
    let delay2 = strategy.nextDelayNanoseconds(attempt: 2, serverRetryMilliseconds: nil)

    #expect(delay0 == 500_000_000)
    #expect(delay1 == 1_000_000_000)
    #expect(delay2 == 2_000_000_000)
}

private struct Payload: Codable, Equatable {
    let value: String
}

@Test func sseEventDecodesPayload() throws {
    let event = SSEEvent(data: #"{"value":"ok"}"#)
    let payload = try event.decodeData(as: Payload.self)
    #expect(payload == Payload(value: "ok"))
}
