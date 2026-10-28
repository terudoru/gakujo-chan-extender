import Foundation

@main
struct MacosHistorySwipeTest {
  static func main() {
    let tracker = MacosHistorySwipeTracker()
    precondition(tracker.add(x: 70, y: 0, time: 1, beginsGesture: true, momentum: false) == nil)
    precondition(tracker.add(x: 60, y: 1, time: 1.1, beginsGesture: false, momentum: false) == true)
    for n in 0..<12 {
      // A long tail, including a pause longer than the idle interval, is still
      // momentum and must not trigger a second history navigation.
      precondition(tracker.add(x: 150, y: 0, time: 2 + Double(n), beginsGesture: false, momentum: true) == nil)
    }
    precondition(tracker.add(x: -130, y: 0, time: 20, beginsGesture: true, momentum: false) == false)
    precondition(tracker.add(x: 10, y: 100, time: 21, beginsGesture: true, momentum: false) == nil)
    precondition(tracker.add(x: 130, y: 0, time: 22, beginsGesture: false, momentum: false) == true)
    print("Mac history swipes: one navigation per gesture including momentum")
  }
}
