import CoreGraphics
import Foundation

/// Goose body speed presets. Selected by tasks.
enum SpeedTier {
    case walk
    case run
    case charge
}

/// The "soul" of the goose: position, velocity, feet animation state, and
/// the currently-running task. Updated every frame; rig + visuals derive
/// from this snapshot.
@MainActor
final class GooseSimulation {
    var screenSize: CGSize = .zero

    var position: CGPoint = CGPoint(x: 300, y: 300)
    var velocity: CGPoint = .zero2
    var direction: CGFloat = 90
    var targetPos: CGPoint = CGPoint(x: 300, y: 300)
    var targetDirection: CGPoint = .zero2

    var currentSpeed: CGFloat = 80
    var currentAcceleration: CGFloat = 1300
    var stepTime: CGFloat = 0.2

    var neckLerpPercent: CGFloat = 0
    var overrideExtendNeck = false

    var lFootPos: CGPoint = .zero2
    var rFootPos: CGPoint = .zero2
    private var lFootMoveOrigin: CGPoint = .zero2
    private var rFootMoveOrigin: CGPoint = .zero2
    private var lFootMoveDir: CGPoint = .zero2
    private var rFootMoveDir: CGPoint = .zero2
    private var lFootMoveTimeStart: CGFloat = -1
    private var rFootMoveTimeStart: CGFloat = -1

    var footMarks: [FootMark] = Array(repeating: FootMark(), count: 64)
    private var footMarkIndex = 0
    var trackMudEndTime: CGFloat = -1

    private(set) var currentTask: GooseTask?

    var onFootLand: (() -> Void)?
    var onHonk: (() -> Void)?
    var onBite: (() -> Void)?

    init() {
        lFootPos = footHome(rightFoot: false)
        rFootPos = footHome(rightFoot: true)
    }

    func setSpeed(_ tier: SpeedTier) {
        switch tier {
        case .walk:
            currentSpeed = 80
            currentAcceleration = 1300
            stepTime = 0.2
        case .run:
            currentSpeed = 200
            currentAcceleration = 1300
            stepTime = 0.2
        case .charge:
            currentSpeed = 400
            currentAcceleration = 2300
            stepTime = 0.1
        }
    }

    func setTask(_ task: GooseTask) {
        currentTask = task
        task.start(simulation: self)
    }

    func tick() {
        GameTime.tick()

        targetDirection = CGPoint.normalize(targetPos - position)
        overrideExtendNeck = false
        currentTask?.tick(simulation: self)

        let smoothed = CGPoint.lerp(.fromAngleDegrees(direction), targetDirection, 0.25)
        direction = atan2(smoothed.y, smoothed.x) * SamMath.rad2Deg

        if CGPoint.magnitude(velocity) > currentSpeed {
            velocity = CGPoint.normalize(velocity) * currentSpeed
        }
        velocity += CGPoint.normalize(targetPos - position) * currentAcceleration * GameTime.deltaTime
        position += velocity * GameTime.deltaTime

        solveFeet()

        let neckTarget: CGFloat = (overrideExtendNeck || currentSpeed >= 200) ? 1 : 0
        neckLerpPercent = SamMath.lerp(neckLerpPercent, neckTarget, 0.075)
    }

    func footHome(rightFoot: Bool) -> CGPoint {
        let bias: CGFloat = rightFoot ? 1 : 0
        let perpendicular = CGPoint.fromAngleDegrees(direction + 90)
        return position + perpendicular * bias * 6
    }

    /// Tip of the goose's beak in world coordinates. Cheap to read each frame
    /// — recomputes the rig from current `position`/`direction`/`neckLerp`.
    /// Used by tasks that need to anchor things (a captured cursor, a stolen
    /// window) to the goose's beak.
    var beakPosition: CGPoint {
        var rig = GooseRig()
        rig.update(position: position, directionDegrees: direction, neckLerp: neckLerpPercent)
        return rig.head2EndPoint
    }

    private func solveFeet() {
        let lHome = footHome(rightFoot: false)
        let rHome = footHome(rightFoot: true)
        let bothFeetIdle = lFootMoveTimeStart < 0 && rFootMoveTimeStart < 0

        if bothFeetIdle {
            if CGPoint.distance(lFootPos, lHome) > 5 {
                beginFootStep(left: true, home: lHome)
                return
            }
            if CGPoint.distance(rFootPos, rHome) > 5 {
                beginFootStep(left: false, home: rHome)
                return
            }
            return
        }

        if lFootMoveTimeStart > 0 {
            advanceFootStep(left: true, home: lHome)
        } else if rFootMoveTimeStart > 0 {
            advanceFootStep(left: false, home: rHome)
        }
    }

    private func beginFootStep(left: Bool, home: CGPoint) {
        let direction = CGPoint.normalize(home - (left ? lFootPos : rFootPos))
        if left {
            lFootMoveOrigin = lFootPos
            lFootMoveDir = direction
            lFootMoveTimeStart = GameTime.time
        } else {
            rFootMoveOrigin = rFootPos
            rFootMoveDir = direction
            rFootMoveTimeStart = GameTime.time
        }
    }

    private func advanceFootStep(left: Bool, home: CGPoint) {
        let moveDir = left ? lFootMoveDir : rFootMoveDir
        let origin = left ? lFootMoveOrigin : rFootMoveOrigin
        let target = home + moveDir * 0.4 * 5
        let startTime = left ? lFootMoveTimeStart : rFootMoveTimeStart
        let elapsed = GameTime.time - startTime

        if elapsed >= stepTime {
            placeFoot(left: left, at: target)
            if left { lFootMoveTimeStart = -1 } else { rFootMoveTimeStart = -1 }
            onFootLand?()
            if GameTime.time < trackMudEndTime {
                addFootMark(at: target)
            }
        } else {
            let p = elapsed / stepTime
            let interpolated = CGPoint.lerp(origin, target, Easings.cubicEaseInOut(p))
            placeFoot(left: left, at: interpolated)
        }
    }

    private func placeFoot(left: Bool, at point: CGPoint) {
        if left {
            lFootPos = point
        } else {
            rFootPos = point
        }
    }

    func addFootMark(at point: CGPoint) {
        footMarks[footMarkIndex] = FootMark(position: point, time: GameTime.time)
        footMarkIndex = (footMarkIndex + 1) % footMarks.count
    }
}
