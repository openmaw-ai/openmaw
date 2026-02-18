import CoreGraphics
import Carbon.HIToolbox
import Foundation

// MARK: - Hotkey Options

enum HotkeyOption: String, CaseIterable {
    case rightOption = "rightOption"
    case leftOption = "leftOption"
    case rightCommand = "rightCommand"
    case leftCommand = "leftCommand"
    case rightControl = "rightControl"
    case fn = "fn"

    var displayName: String {
        switch self {
        case .rightOption: return "Right Option (\u{2325})"
        case .leftOption: return "Left Option (\u{2325})"
        case .rightCommand: return "Right Command (\u{2318})"
        case .leftCommand: return "Left Command (\u{2318})"
        case .rightControl: return "Right Control (\u{2303})"
        case .fn: return "Fn (Globe)"
        }
    }

    var keyCode: Int64 {
        switch self {
        case .rightOption: return Int64(kVK_RightOption)
        case .leftOption: return Int64(kVK_Option)
        case .rightCommand: return Int64(kVK_RightCommand)
        case .leftCommand: return Int64(kVK_Command)
        case .rightControl: return Int64(kVK_RightControl)
        case .fn: return Int64(kVK_Function)
        }
    }

    var flagMask: CGEventFlags {
        switch self {
        case .rightOption, .leftOption: return .maskAlternate
        case .rightCommand, .leftCommand: return .maskCommand
        case .rightControl: return .maskControl
        case .fn: return .maskSecondaryFn
        }
    }
}

// MARK: - Hotkey Manager

final class HotkeyManager {
    var onTap: (() -> Void)?
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?

    private var keyDownTime: UInt64 = 0
    private var isHolding = false
    private var holdTimer: DispatchSourceTimer?

    private let holdThresholdNs: UInt64

    init() {
        holdThresholdNs = UInt64(Config.shared.holdThresholdMs) * 1_000_000
    }

    private var tapRunLoop: CFRunLoop?

    func start() {
        tapThread = Thread {
            self.tapRunLoop = CFRunLoopGetCurrent()
            self.setupEventTap()
            CFRunLoopRun()
        }
        tapThread?.name = "HotkeyManager"
        tapThread?.start()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
        }
        if let rl = tapRunLoop {
            CFRunLoopStop(rl)
        }
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil
    }

    /// Tear down and recreate the event tap. Call after system wake.
    func restart() {
        stop()
        start()
    }

    private func setupEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            manager.handleFlagsChanged(event: event)
            return Unmanaged.passRetained(event)
        }

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: refcon
        ) else {
            print("Failed to create event tap. Check Accessibility permissions.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleFlagsChanged(event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let hotkey = Config.shared.hotkeyCode

        guard keyCode == hotkey.keyCode else { return }

        let flags = event.flags
        let keyPressed = flags.contains(hotkey.flagMask)

        if keyPressed {
            // Key down
            keyDownTime = mach_absolute_time()
            isHolding = false

            // Start hold timer
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + .milliseconds(Config.shared.holdThresholdMs))
            timer.setEventHandler { [weak self] in
                guard let self = self else { return }
                self.isHolding = true
                self.onHoldStart?()
            }
            timer.resume()
            holdTimer = timer
        } else {
            // Key up
            holdTimer?.cancel()
            holdTimer = nil

            if isHolding {
                // Was holding — signal hold end
                isHolding = false
                DispatchQueue.main.async { [weak self] in
                    self?.onHoldEnd?()
                }
            } else {
                // Quick tap
                DispatchQueue.main.async { [weak self] in
                    self?.onTap?()
                }
            }
        }
    }
}
