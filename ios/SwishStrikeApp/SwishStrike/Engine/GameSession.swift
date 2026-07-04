import CoreMedia
import Foundation
import Observation
import SwishStrikeCore
import os

/// The per-game orchestrator — the Swift mirror of web-prototype/js/app.js.
/// One pipeline regardless of source:
///   camera frame → BallDetecting  ─┐
///   deterministic SimSource       ─┴→ BallTracker → CountingEngine → feel layer
/// The engine's rule comes from the game itself (GameCatalog → buildRule), so
/// every game counts by its own definition: hoop makes, streaks with misses,
/// bounce reps. All UI-facing state is @MainActor.
@MainActor
@Observable
final class GameSession {
    enum Phase { case setup, play, result }
    enum CameraPermission { case unknown, granted, denied }

    let game: Game
    private(set) var phase: Phase = .setup
    private(set) var source: SourceMode
    private(set) var permission: CameraPermission = .unknown

    // Live play state the views render.
    private(set) var count = 0
    private(set) var maxStreak = 0
    private(set) var lastQuality: String?          // "swish" | "rim" | nil
    private(set) var toast: String?
    private(set) var ballPosition: (x: Double, y: Double)?
    private(set) var heatLevel: Double = 0
    private(set) var onFire = false
    private(set) var missFlash = 0                 // increments on each miss (drives shake)
    private(set) var scoreTick = 0                 // increments on each make (drives pop)
    private(set) var savedArc: [(x: Double, y: Double)] = []
    private(set) var swishCount = 0
    private(set) var rimCount = 0
    private(set) var isNewPersonalBest = false
    private(set) var activeZone: Zone?

    // Setup coaching.
    private(set) var coachPrimary = "Scanning for the target"
    private(set) var coachHints: [String] = []
    private(set) var coachReady = false

    // Pipeline (owned; touched only on the main actor). The engine is recreated
    // whenever the rule's zone changes — same lifecycle as the web app.
    private var engine: CountingEngine
    private let tracker = BallTracker()
    private let trail = TrailBuffer()
    private let heat = Heat()
    private let sim: SimSource
    private let camera = CameraManager()
    private let detector: BallDetecting
    private var startBest = 0
    private var pbCelebrated = false
    private var wasOnFire = false
    private var readyFrames = 0
    private var cameraTimeOffset: Double?
    private var simTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private let started = ContinuousClock.now
    private let log = Logger(subsystem: Log.subsystem, category: "session")

    private static let qualityFlavor: [String: [String]] = [
        "swish": ["Swish!", "Nothing but net.", "Cash!", "Splash!"],
        "rim": ["Rattles in!", "Shooter's roll.", "Off the iron — counts.", "Friendly bounce."],
    ]

    init(game: Game, detector: BallDetecting? = nil) {
        self.game = game
        self.source = AppFlags.startupSource
        self.sim = SimSource(game: game)
        self.detector = detector ?? TrajectoryBallDetector()
        self.activeZone = game.defaultZone
        self.engine = CountingEngine(rule: game.buildRule(zoneOverride: game.defaultZone))
    }

    private var now: Double {
        Double(started.duration(to: .now).components.seconds)
            + Double(started.duration(to: .now).components.attoseconds) / 1e18
    }

    // MARK: - Lifecycle

    func start() {
        Haptics.shared.prepare()
        startBest = PersistenceStore.shared.best(for: game.slug)
        enterSetup()
        if source == .camera { startCamera() } else { startSimLoop() }
    }

    func stop() {
        simTask?.cancel(); simTask = nil
        camera.onFrame = nil
        camera.stop()
    }

    func setSource(_ new: SourceMode) {
        guard new != source else { return }
        stop()
        source = new
        AppFlags.preferredSource = new
        start()
    }

    private func startCamera() {
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.camera.requestAccess()
            self.permission = granted ? .granted : .denied
            guard granted else { return }
            self.camera.configure()
            let detector = self.detector
            self.cameraTimeOffset = nil
            self.camera.onFrame = { [weak self] buffer, t in
                // Vision runs here on the camera's sample queue, off the UI.
                let ball = detector.detect(sampleBuffer: buffer, time: t)
                Task { @MainActor in
                    guard let self else { return }
                    // Capture timestamps are on the boot clock; the overlay and
                    // trail sample `clock` (session-relative). Rebase once so
                    // both sides of the feel layer share one time domain.
                    let offset = self.cameraTimeOffset ?? (t - self.now)
                    self.cameraTimeOffset = offset
                    self.ingest(ball: ball, t: t - offset)
                }
            }
            self.camera.start()
            // Camera setup is manual: aim, tap to place the target, start.
            self.coachPrimary = self.game.needsTarget
                ? "Aim at the target, then tap the view to place the zone"
                : "Frame the play area, then start"
            self.coachHints = [self.game.instructions]
            self.coachReady = true
        }
    }

    var cameraSession: CameraManager { camera }

    private func startSimLoop() {
        permission = .granted
        simTask?.cancel()
        simTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let t = self.now
                switch self.phase {
                case .setup: self.simSetupTick(t)
                case .play:
                    let frame = self.sim.play(t: t)
                    self.ingest(ball: frame.ball.map { ($0.x, $0.y, $0.confidence) }, t: t)
                case .result: break
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    // MARK: - Setup

    private func enterSetup() {
        phase = .setup
        readyFrames = 0
        coachReady = false
        coachPrimary = "Scanning for the target"
        coachHints = []
    }

    private func simSetupTick(_ t: Double) {
        let signals = sim.calibration(t: t)
        let verdict = SetupCoach.evaluate(.init(
            targetVisible: signals.targetVisible,
            targetBox: signals.targetBox.map { CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) },
            brightness: signals.brightness,
            bodyVisible: signals.bodyVisible,
            needsBody: game.needsBody))
        coachPrimary = verdict.primary
        coachHints = verdict.hints
        coachReady = verdict.ready
        if verdict.ready {
            readyFrames += 1
            if readyFrames >= 18 {   // ~0.6s of stable ready — same gate as the web
                if let box = signals.targetBox, game.defaultZone != nil {
                    activeZone = Zone(left: box.x, top: box.y,
                                      right: box.x + box.w, bottom: box.y + box.h)
                }
                enterPlay()
            }
        } else {
            readyFrames = 0
        }
    }

    func beginPlay() { enterPlay() }

    private func enterPlay() {
        phase = .play
        engine = CountingEngine(rule: game.buildRule(zoneOverride: activeZone))
        tracker.reset()
        detector.reset()
        trail.clear()
        heat.reset()
        count = 0; maxStreak = 0; swishCount = 0; rimCount = 0
        pbCelebrated = false; wasOnFire = false; isNewPersonalBest = false
        savedArc = []
    }

    /// Tap-to-place: recenters the target zone at a normalized point, exactly
    /// like the web. During play the engine restarts so the new zone is fair.
    func placeTarget(atNormalized x: Double, y: Double) {
        guard let base = game.defaultZone else { return }
        let hw = (base.right - base.left) / 2, hh = (base.bottom - base.top) / 2
        let clamp = { (v: Double) in min(1, max(0, v)) }
        activeZone = Zone(left: clamp(x - hw), top: clamp(y - hh),
                          right: clamp(x + hw), bottom: clamp(y + hh))
        if phase == .play { enterPlay() }
        showToast("Target placed")
    }

    // MARK: - The frame pipeline

    private func ingest(ball: (x: Double, y: Double, confidence: Double)?, t: Double) {
        guard phase == .play else { return }
        let tracked = tracker.update(x: ball?.x, y: ball?.y, t: t)
        let valid = tracked?.valid ?? false
        let confidence: Double = if valid && !(tracked?.coasting ?? true) {
            ball?.confidence ?? 0.8
        } else {
            valid ? 0.5 : 0
        }
        if valid, let p = tracked {
            ballPosition = (p.x, p.y)
            trail.push(now: t, x: p.x, y: p.y)
        }
        heatLevel = heat.tick(now: t)
        onFire = heat.onFire
        if !heat.onFire { wasOnFire = false }

        let fired = engine.update(Sample(t: t, x: tracked?.x, y: tracked?.y, confidence: confidence))
        if fired { onScore(t: t) } else if engine.justMissed { onMiss() }
        count = engine.count
    }

    /// Trail segments for the overlay, freshest last.
    func trailPoints(at t: Double) -> [TrailPoint] { trail.live(now: t) }
    var clock: Double { now }

    private func onScore(t: Double) {
        let quality = engine.lastEvent?.quality
        lastQuality = quality
        if quality == "swish" { swishCount += 1 }
        if quality == "rim" { rimCount += 1 }
        maxStreak = max(maxStreak, engine.count)
        heat.bump()
        savedArc = trail.snapshotArc(now: t)
        scoreTick += 1

        let flavors = quality.flatMap { Self.qualityFlavor[$0] } ?? ["\(game.tag)!"]
        showToast("\(flavors[(engine.count - 1 + flavors.count) % flavors.count])  ·  \(engine.count)")

        switch quality {
        case "swish": Sfx.shared.play(.swish); Haptics.shared.swish()
        case "rim": Sfx.shared.play(.rim); Haptics.shared.rim()
        default: Sfx.shared.play(.pop); Haptics.shared.swish()
        }
        if heat.onFire && !wasOnFire { Sfx.shared.play(.streak); wasOnFire = true }
        if !pbCelebrated && startBest > 0 && engine.count > startBest {
            pbCelebrated = true
            isNewPersonalBest = true
            Sfx.shared.play(.personalBest)
            Haptics.shared.personalBest()
            showToast("New best — \(engine.count)")
        }
        _ = PersistenceStore.shared.recordCount(engine.count, for: game.slug)
    }

    private func onMiss() {
        missFlash += 1
        heat.reset()
        wasOnFire = false
        Sfx.shared.play(.miss)
        Haptics.shared.miss()
        showToast("Streak broken")
    }

    // MARK: - Result

    func finish() {
        phase = .result
        let headline = game.buildRule().type == .zoneStreak ? maxStreak : engine.count
        isNewPersonalBest = startBest > 0 && headline > startBest
        _ = PersistenceStore.shared.recordCount(headline, for: game.slug)
    }

    var resultHeadline: Int {
        game.buildRule().type == .zoneStreak ? maxStreak : count
    }

    func playAgain() { enterSetup() }

    private func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_300))
            if !Task.isCancelled { self?.toast = nil }
        }
    }
}
