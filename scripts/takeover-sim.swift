// Simulation of TakeoverSequencer (extracted from MonitorSwitcher.swift by scripts/test.sh) on a
// virtual clock: no SSH, no monitor, no windows. Prints "PASS <name>" / "FAIL <name>" per scenario.
import Foundation

enum Sim {
    static var now = 0.0
    private static var events: [(t: Double, n: Int, work: () -> Void)] = []
    private static var counter = 0
    static func at(_ t: Double, _ work: @escaping () -> Void) { counter += 1; events.append((t, counter, work)) }
    static func reset() { now = 0; events = []; counter = 0 }
    static func runAll(until end: Double = 300) {
        while let i = events.indices.min(by: { (events[$0].t, events[$0].n) < (events[$1].t, events[$1].n) }) {
            let e = events.remove(at: i)
            guard e.t <= end else { break }
            now = e.t
            e.work()
        }
    }
}

/// The laptop, the network and the shared monitor. `run` keeps the app's contract: a switch that
/// arrives while another one is running is refused at once (completion false); otherwise it takes
/// 0.5 s with the network up or 5 s (SSH ConnectTimeout) without it, then calls runFinished().
final class World {
    var input = "mini", netUp = true, busy = false, connected = true
    var log: [(t: Double, what: String)] = []
    let seq = TakeoverSequencer()

    init() {
        seq.isBusy = { [unowned self] in self.busy }
        seq.mayClaim = { [unowned self] in self.connected }
        seq.after = { seconds, work in Sim.at(Sim.now + seconds, work) }
        seq.run = { [unowned self] arg, done in
            guard !self.busy else { self.note("\(arg) refused"); done(false); return }
            self.busy = true
            let ok = self.netUp
            self.note("\(arg) start")
            Sim.at(Sim.now + (ok ? 0.5 : 5)) {
                self.busy = false
                if ok { self.input = arg == "macbook" ? "macbook" : "mini" }
                self.note("\(arg) \(ok ? "ok" : "failed")")
                done(ok)
                self.seq.runFinished()
            }
        }
    }

    func note(_ what: String) { log.append((Sim.now, what)) }
    func count(_ what: String, after t: Double = -1) -> Int { log.filter { $0.t > t && $0.what == what }.count }
    /// What AutoTakeover does: unplugged -> cancel retries now, release later.
    func unplug(at t: Double) { Sim.at(t) { self.connected = false; self.seq.cancelTakeover() } }
    func plug(at t: Double) { Sim.at(t) { self.connected = true; self.seq.takeOver() } }
    func network(_ up: Bool, at t: Double) { Sim.at(t) { self.netUp = up } }
}

var failures = 0
func scenario(_ name: String, _ setup: (World) -> Void, _ expect: (World) -> Bool) {
    Sim.reset()
    let w = World()
    setup(w)
    Sim.runAll()
    let ok = expect(w)
    if !ok { failures += 1 }
    print((ok ? "PASS " : "FAIL ") + name)
    if !ok { for e in w.log { FileHandle.standardError.write("    t=\(e.t) \(e.what)\n".data(using: .utf8)!) } }
}

scenario("network up: claimed at once, one attempt") { w in
    w.plug(at: 0)
} _: { w in w.input == "macbook" && w.count("macbook start") == 1 }

scenario("Wi-Fi back after a failed attempt: the retry still claims") { w in
    w.netUp = false; w.plug(at: 0); w.network(true, at: 7)
} _: { w in w.input == "macbook" && w.count("macbook start") == 2 }

scenario("network never returns: gives up after 6 attempts") { w in
    w.netUp = false; w.plug(at: 0)
} _: { w in w.input == "mini" && w.count("macbook start") == 6 }

// C1-R2 S3: unplugged at 20 s, release at 25 s; no stale retry may claim the monitor afterwards.
scenario("unplugged during retries: no claim after unplug, ends on the server") { w in
    w.netUp = false; w.plug(at: 0); w.unplug(at: 20); w.network(true, at: 24)
    Sim.at(25) { w.seq.release {} }
} _: { w in w.input == "mini" && w.count("macbook start", after: 20) == 0 && w.count("release ok") == 1 }

// C1-R2 S4: release arrives while an attempt is running – it is queued, not dropped.
var released = 0
scenario("release during a running attempt: queued, runs after it, completion once") { w in
    released = 0
    w.netUp = false; w.plug(at: 0); w.unplug(at: 2); w.network(true, at: 4)
    Sim.at(3) { w.seq.release { released += 1 } }
} _: { w in
    w.input == "mini" && released == 1 && w.count("release refused") == 0
        && w.count("release ok") == 1 && w.count("macbook start") == 1
}

scenario("sleep release (shared monitor still attached) stops retries") { w in
    w.netUp = false; w.plug(at: 0); w.network(true, at: 10)
    Sim.at(6) { w.seq.release {} }   // between attempt 1 and its retry at 9 s
} _: { w in w.input == "mini" && w.count("macbook start", after: 6) == 0 }

var waiterCalls = 0
scenario("plugged in again before a queued release: release dropped, waiter called, claimed") { w in
    waiterCalls = 0
    w.netUp = false; w.plug(at: 0); w.unplug(at: 2)
    Sim.at(3) { w.seq.release { waiterCalls += 1 } }
    w.network(true, at: 3.5); w.plug(at: 4)
} _: { w in w.input == "macbook" && waiterCalls == 1 && w.count("release start") == 0 }

exit(failures == 0 ? 0 : 1)
