import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  private let state = NotificationActivationHandoff()
  private var live: [(url: String, token: String?, reply: (Bool) -> Void)] = []

  override func setUp() {
    super.setUp()
    state.deliver = { [unowned self] in self.live.append(($0, $1, $2)) }
  }

  func testLatestPendingReceiptAndEverySubsequentActivation() {
    state.receive("A")
    state.receive("B")
    XCTAssertTrue(live.isEmpty)
    XCTAssertEqual(state.take("run:1"), "B")
    state.receive("B")
    state.receive("A")
    XCTAssertEqual(live.map { $0.url }, ["B", "A"])
    XCTAssertEqual(state.take("run:1"), "B")
    state.finish("run:1", accepted: true)
    XCTAssertNil(state.take("run:1"))
  }

  func testSupersededAcknowledgements() {
    for (index, url) in ["A", "B"].enumerated() {
      for accepted in [false, true] {
        let run = "trial\(index)\(accepted)"
        _ = state.take(run + ":1")
        state.receive("A")
        state.receive(url)
        let old = live[live.count - 2]
        live.last!.reply(accepted)
        old.reply(!accepted)
        XCTAssertNil(state.take(run + ":1"))
        XCTAssertEqual(state.take(run + ":2"), accepted ? nil : url)
        state.finish(run + ":2", accepted: true)
      }
    }
  }

  func testUnsettledWorkAndReplacementConsumer() {
    XCTAssertNil(state.take("run:1"))
    state.receive("A")
    state.end("run:1")
    XCTAssertNil(state.take("run:2"))
    state.end("run:1")
    live[0].reply(false)
    XCTAssertEqual(live.map { $0.token }, ["run:1", "run:2"])
    live[1].reply(false)
    XCTAssertEqual(live.count, 2)
    XCTAssertNil(state.take("run:1"))
    XCTAssertEqual(state.take("run:3"), "A")
    XCTAssertNil(state.take("run:4"))
    state.finish("run:3", accepted: false)
    XCTAssertEqual(live.last?.token, "run:4")
    live.last!.reply(true)
    XCTAssertNil(state.take("run:5"))
  }

  func testTakeoverAndMessengerReplacementFenceReplies() {
    _ = state.take("run:1")
    state.receive("A")
    XCTAssertEqual(state.take("restart:1"), "A")
    live[0].reply(true)
    state.end("run:1")
    XCTAssertNil(state.take("run:1"))
    XCTAssertEqual(state.take("restart:1"), "A")
    state.finish("restart:1", accepted: true)
    state.receive("B")
    state.replaceMessenger()
    XCTAssertEqual(state.take("restart:1"), "B")
    live.last!.reply(true)
    XCTAssertEqual(state.take("restart:1"), "B")
    state.finish("restart:1", accepted: false)
    XCTAssertEqual(state.take("restart:2"), "B")
  }

  func testOldSuccessCannotSettleSameURLStillInFlight() {
    _ = state.take("run:1")
    state.receive("A")
    state.receive("A")
    live[0].reply(true)
    XCTAssertNil(state.take("run:2"))
    live[1].reply(false)
    XCTAssertEqual(live.count, 3)
    XCTAssertEqual(live[2].token, "run:2")
    live[2].reply(true)
    XCTAssertNil(state.take("run:3"))
  }

  func testLegacyStartupAndUntaggedLive() {
    state.receive("A")
    XCTAssertEqual(state.takeLegacy(), "A")
    XCTAssertNil(state.takeLegacy())
    state.receive("B")
    XCTAssertEqual(live.count, 1)
    XCTAssertNil(live[0].token)
    live[0].reply(false)
    XCTAssertEqual(state.takeLegacy(), "B")
  }

}
