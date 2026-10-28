import Foundation

/// Groups a trackpad's scroll and momentum events into one navigation.
final class MacosHistorySwipeTracker {
  private var distance: Double = 0
  private var triggered = false
  private var lastEvent: TimeInterval?

  func add(x: Double, y: Double, time: TimeInterval,
           beginsGesture: Bool, momentum: Bool) -> Bool? {
    if beginsGesture || (!momentum && lastEvent.map({ time - $0 > 0.25 }) == true) {
      reset()
    }
    lastEvent = time
    if triggered { return nil }
    if abs(x) <= abs(y) * 1.25 { return nil }
    distance += x
    if abs(distance) < 120 { return nil }
    triggered = true
    return distance > 0
  }

  func reset() {
    distance = 0
    triggered = false
    lastEvent = nil
  }
}
