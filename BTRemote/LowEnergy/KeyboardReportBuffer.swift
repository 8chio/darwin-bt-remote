import Foundation

/// Keep keyboard edges in order when CoreBluetooth applies backpressure.
/// Other HID report types retain their existing coalescing behavior.
struct KeyboardReportBuffer {
    struct Delivery {
        let report: KeyboardReport
        let boot: Bool
    }

    private var deliveries: [Delivery] = []
    private let capacity = 256
    var first: Delivery? { deliveries.first }
    var count: Int { deliveries.count }

    /// On overflow discard stale typing and retain a neutral report for both paths.
    @discardableResult
    mutating func append(_ report: KeyboardReport) -> Bool {
        guard deliveries.count + 2 <= capacity else {
            clear()
            deliveries = [Delivery(report: .zero, boot: false), Delivery(report: .zero, boot: true)]
            return false
        }
        deliveries += [Delivery(report: report, boot: false), Delivery(report: report, boot: true)]
        return true
    }

    mutating func removeFirst() { if !deliveries.isEmpty { deliveries.removeFirst() } }
    mutating func clear() { deliveries.removeAll() }
}
