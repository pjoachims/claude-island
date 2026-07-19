import AppKit
import Carbon.HIToolbox
import Combine
import SwiftTerm
import SwiftUI

// MARK: - Hotkey presets

struct HotKeyPreset {
    let id: String
    let label: String
    let keyCode: UInt32
    let mods: UInt32
}

let hotKeyPresets: [HotKeyPreset] = [
    .init(id: "ctrl-opt-space", label: "⌃⌥ Space", keyCode: UInt32(kVK_Space), mods: UInt32(controlKey | optionKey)),
    .init(id: "opt-space", label: "⌥ Space", keyCode: UInt32(kVK_Space), mods: UInt32(optionKey)),
    .init(id: "cmd-shift-space", label: "⌘⇧ Space", keyCode: UInt32(kVK_Space), mods: UInt32(cmdKey | shiftKey)),
    .init(id: "ctrl-opt-c", label: "⌃⌥ C", keyCode: UInt32(kVK_ANSI_C), mods: UInt32(controlKey | optionKey)),
    .init(id: "ctrl-opt-i", label: "⌃⌥ I", keyCode: UInt32(kVK_ANSI_I), mods: UInt32(controlKey | optionKey)),
    .init(id: "off", label: "Off", keyCode: 0, mods: 0),
]

// MARK: - Model

final class Store: ObservableObject {
    @Published var expanded = false
    @Published var resizing = false // drag in progress: show bare black box
    @Published var autoFocus: Bool = UserDefaults.standard.object(forKey: "autoFocus") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoFocus, forKey: "autoFocus") }
    }
    @Published var hotkey: String = UserDefaults.standard.string(forKey: "hotkey") ?? "ctrl-opt-space" {
        didSet { UserDefaults.standard.set(hotkey, forKey: "hotkey") }
    }
    @Published var launchDir: String = UserDefaults.standard.string(forKey: "launchDir")
        ?? NSHomeDirectory() + "/Documents/git" {
        didSet { UserDefaults.standard.set(launchDir, forKey: "launchDir") }
    }
    // user-dragged terminal size; panel chrome is added around it
    @Published var termW: CGFloat = UserDefaults.standard.object(forKey: "termW") as? CGFloat ?? 556 {
        didSet { UserDefaults.standard.set(termW, forKey: "termW") }
    }
    @Published var termH: CGFloat = UserDefaults.standard.object(forKey: "termH") as? CGFloat ?? 440 {
        didSet { UserDefaults.standard.set(termH, forKey: "termH") }
    }
    // ~/Documents/git itself + every git repo directly under it
    let repoChoices: [String] = {
        let root = NSHomeDirectory() + "/Documents/git"
        let fm = FileManager.default
        let subs = (try? fm.contentsOfDirectory(atPath: root)) ?? []
        return [root] + subs.sorted().compactMap { name in
            let p = root + "/" + name
            return fm.fileExists(atPath: p + "/.git") ? p : nil
        }
    }()
}

// MARK: - Embedded `claude agents` terminal

final class IslandTerminalView: LocalProcessTerminalView {
    // accessory app has no Edit menu, so ⌘V never reaches paste(_:) on its own
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
            paste(self)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // image on the clipboard (e.g. a screenshot): Claude Code reads the clipboard
    // itself when it sees ^V, so replay ⌘V as a ^V keypress and let it do the work
    override func paste(_ sender: Any) {
        let pb = NSPasteboard.general
        if pb.string(forType: .string) == nil, NSImage(pasteboard: pb) != nil {
            if let ev = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.control],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window?.windowNumber ?? 0, context: nil,
                characters: "\u{16}", charactersIgnoringModifiers: "v",
                isARepeat: false, keyCode: UInt16(kVK_ANSI_V)) {
                keyDown(with: ev)
            }
            return
        }
        super.paste(sender)
    }
}

final class TermHost: NSObject, LocalProcessTerminalViewDelegate {
    static let shared = TermHost()
    private(set) var view: LocalProcessTerminalView?

    func terminal() -> LocalProcessTerminalView {
        if let v = view { return v }
        // boot at the persisted size so the TUI lays out right before first expand
        let w = UserDefaults.standard.object(forKey: "termW") as? CGFloat ?? 556
        let h = UserDefaults.standard.object(forKey: "termH") as? CGFloat ?? 440
        let t = IslandTerminalView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        t.processDelegate = self
        t.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        t.nativeBackgroundColor = .black
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        let cwd = UserDefaults.standard.string(forKey: "launchDir")
            ?? NSHomeDirectory() + "/Documents/git"
        t.startProcess(
            executable: "/bin/zsh",
            args: ["-lc", "cd '\(cwd)' && exec ~/.local/bin/claude agents"],
            environment: env.map { "\($0.key)=\($0.value)" },
            execName: nil)
        view = t
        return t
    }

    func shutdown() {
        // claude agents is a singleton TUI; an orphan blocks the next launch
        if let v = view { kill(v.process.shellPid, SIGHUP) }
        view = nil
    }

    // respawn on next expand if the TUI exits
    func processTerminated(source: TerminalView, exitCode: Int32?) { view = nil }
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}

struct TerminalPane: NSViewRepresentable {
    func makeNSView(context: Context) -> LocalProcessTerminalView { TermHost.shared.terminal() }
    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}
}

// MARK: - Views

struct IslandView: View {
    @ObservedObject var store: Store
    var notchH: CGFloat
    var onHover: (Bool) -> Void
    var onResize: (Bool) -> Void // ended?

    var body: some View {
        // overlays don't inflate layout: a fixed-size child in a ZStack made the
        // root bigger than the pill window, pushing bottom content (and the
        // rounded corners) outside the visible frame
        UnevenRoundedRectangle(
            bottomLeadingRadius: store.expanded ? 14 : 18,
            bottomTrailingRadius: store.expanded ? 14 : 18)
            .fill(.black)
            .overlay(alignment: .top) {
                // always attached at the chosen size so the pty never sees pill-sized
                // resizes (they made the TUI reflow to ~40 cols and stick there)
                TerminalPane()
                    .id(store.launchDir) // dir change -> fresh terminal + TUI
                    .frame(width: store.termW, height: store.termH)
                    .padding(.top, notchH + 8)
                    .opacity(store.expanded && !store.resizing ? 1 : 0)
                    .allowsHitTesting(store.expanded && !store.resizing)
            }
            .overlay(alignment: .bottomTrailing) {
                if store.expanded { resizeGrip }
            }
            .onHover { onHover($0) }
            .contextMenu {
                Toggle("Auto-focus keyboard on hover", isOn: $store.autoFocus)
                Picker("New sessions start in", selection: $store.launchDir) {
                    ForEach(store.repoChoices, id: \.self) { p in
                        Text(p == NSHomeDirectory() + "/Documents/git"
                            ? "~/Documents/git" : (p as NSString).lastPathComponent)
                            .tag(p)
                    }
                }
                Picker("Toggle Shortcut", selection: $store.hotkey) {
                    ForEach(hotKeyPresets, id: \.id) { p in
                        Text(p.label).tag(p.id)
                    }
                }
                Button("Quit Claude Island") { NSApp.terminate(nil) }
            }
    }

    // drag to resize the expanded island; AppDelegate tracks the mouse in screen
    // coords (gesture translation is useless inside a live-resizing view)
    var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.gray.opacity(0.7))
            .padding(8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onResize(false) }
                    .onEnded { _ in onResize(true) })
    }
}

// MARK: - App

final class IslandPanel: NSPanel {
    // borderless panels refuse key status by default; without it SwiftUI taps never fire
    override var canBecomeKey: Bool { true }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    // without this, the first click on the non-active panel is swallowed as an activation click
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    let store = Store()
    var hovering = false
    var bag = Set<AnyCancellable>()

    var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }
    var notchH: CGFloat { max(screen.safeAreaInsets.top, 0) }
    var notchW: CGFloat {
        let s = screen
        if let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            return s.frame.width - l.width - r.width
        }
        return 160
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        panel = IslandPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = IslandView(
            store: store, notchH: notchH,
            onHover: { [weak self] hover in self?.hoverChanged(hover) },
            onResize: { [weak self] ended in self?.resizeDrag(ended: ended) })
        let hosting = FirstMouseHostingView(rootView: view)
        hosting.sizingOptions = [] // never let SwiftUI intrinsic size fight setFrame
        panel.contentView = hosting
        _ = TermHost.shared.terminal() // boot the TUI before the first expand
        applyHotKey()
        store.$hotkey
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyHotKey() }
            .store(in: &bag)

        // kill the old TUI before SwiftUI (.id change) attaches a fresh one
        store.$launchDir
            .dropFirst()
            .sink { _ in TermHost.shared.shutdown() }
            .store(in: &bag)
        setExpanded(false)
        panel.orderFrontRegardless()

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.typedSinceExpand = true
            return e
        }

        // collapse when keyboard focus leaves the embedded terminal (click in another app)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            self?.scheduleCollapse()
        }
    }

    var collapseTimer: Timer?
    var typedSinceExpand = false

    func applicationWillTerminate(_ notification: Notification) {
        TermHost.shared.shutdown()
    }

    func hoverChanged(_ h: Bool) {
        hovering = h
        if h {
            collapseTimer?.invalidate()
            collapseTimer = nil
            setExpanded(true)
        } else {
            scheduleCollapse()
        }
    }

    // SwiftUI hover events flap during the frame animation; trust the actual
    // mouse position instead and only collapse once it has really left.
    func scheduleCollapse() {
        guard collapseTimer == nil, store.expanded else { return }
        collapseTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.dragStartSize != nil { return } // never collapse mid-resize
            if self.panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) { return }
            // pinned only when the user actually typed into the terminal
            if self.panel.isKeyWindow && self.typedSinceExpand { return }
            self.collapseTimer?.invalidate()
            self.collapseTimer = nil
            self.setExpanded(false)
        }
    }

    // Resize drag: the real panel (SwiftUI + terminal) is expensive to resize
    // per mouse tick and flickers. So during the drag the panel goes invisible
    // and a dumb layer-backed black window tracks the mouse — pure window-server
    // ops, nothing re-renders. On release the panel snaps to the final size and
    // the pty reflows once, still hidden.
    var dragStartMouse: NSPoint?
    var dragStartSize: CGSize?

    lazy var ghost: NSPanel = {
        let g = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        g.level = .statusBar
        g.backgroundColor = .clear
        g.isOpaque = false
        g.hasShadow = false
        g.ignoresMouseEvents = true
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.black.cgColor
        v.layer?.cornerRadius = 14
        v.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        g.contentView = v
        return g
    }()

    func resizeDrag(ended: Bool) {
        let sc = screen
        if dragStartMouse == nil {
            dragStartMouse = NSEvent.mouseLocation
            dragStartSize = CGSize(width: store.termW, height: store.termH)
            store.resizing = true // hide the terminal for the end-of-drag reflow
            ghost.setFrame(panel.frame, display: false)
            ghost.orderFrontRegardless()
            panel.alphaValue = 0 // keeps key status, unlike orderOut
        }
        guard let m0 = dragStartMouse, let s0 = dragStartSize else { return }
        let m = NSEvent.mouseLocation
        // panel is centered on the notch, so the right edge only moves half of
        // any width change — double dx so the grip stays under the cursor
        let w = min(max(400, s0.width + (m.x - m0.x) * 2), sc.frame.width - 64)
        let h = min(max(240, s0.height + (m0.y - m.y)), sc.frame.height * 0.8 - notchH - 24)
        if ended {
            dragStartMouse = nil
            dragStartSize = nil
            store.termW = w
            store.termH = h
            setExpanded(true) // snap panel to the final size, reflow the pty once
            panel.alphaValue = 1
            ghost.orderOut(nil)
            // let the TUI redraw at the new size before unveiling it
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.store.resizing = false
            }
            return
        }
        let pw = max(notchW + 40, w + 24)
        let ph = notchH + 8 + h + 16
        ghost.setFrame(
            NSRect(x: sc.frame.midX - pw / 2, y: sc.frame.maxY - ph, width: pw, height: ph),
            display: true)
    }

    func setExpanded(_ e: Bool) {
        let wasExpanded = store.expanded
        store.expanded = e
        // hand the keyboard back to whatever app had it before auto-focus
        if !e, panel.isKeyWindow { panel.orderOut(nil) }
        let sc = screen
        let w: CGFloat
        let h: CGFloat
        if e {
            w = max(notchW + 40, store.termW + 24)
            h = min(notchH + 8 + store.termH + 16, sc.frame.height * 0.8)
        } else {
            w = notchW + 16
            h = (notchH > 0 ? notchH : 22) + 18
        }
        let f = NSRect(
            x: sc.frame.midX - w / 2,
            y: sc.frame.maxY - h,
            width: w, height: h)
        if f != panel.frame {
            // animate only expand/collapse transitions; drag-resize must track 1:1
            panel.setFrame(
                f, display: true,
                animate: e != wasExpanded || (!e && panel.frame.width > 0))
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
        if e && !wasExpanded {
            typedSinceExpand = false
            if store.autoFocus { focusPrompt() }
        }
    }

    // cursor straight into the FleetView prompt — type immediately
    func focusPrompt() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.store.expanded else { return }
            self.panel.makeKey()
            if let t = TermHost.shared.view { self.panel.makeFirstResponder(t) }
        }
    }

    func toggleIsland() {
        if store.expanded {
            setExpanded(false)
        } else {
            setExpanded(true)
            typedSinceExpand = true // pin until the user clicks elsewhere or toggles
            focusPrompt() // explicit invocation always focuses, ignores autoFocus
        }
    }

    // `open`ing the app while it runs lands here — lets Raycast (or any
    // launcher hotkey bound to the app) toggle the island
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        toggleIsland()
        return false
    }

    var hotKeyRef: EventHotKeyRef?
    var hotKeyHandlerInstalled = false

    func applyHotKey() {
        if let r = hotKeyRef {
            UnregisterEventHotKey(r)
            hotKeyRef = nil
        }
        guard let p = hotKeyPresets.first(where: { $0.id == store.hotkey }), p.id != "off"
        else { return }
        if !hotKeyHandlerInstalled {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(
                GetEventDispatcherTarget(),
                { _, _, userData in
                    Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue().toggleIsland()
                    return noErr
                },
                1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
            hotKeyHandlerInstalled = true
        }
        RegisterEventHotKey(
            p.keyCode, p.mods,
            EventHotKeyID(signature: OSType(0x434C_4953), id: 1),
            GetEventDispatcherTarget(), 0, &hotKeyRef)
    }
}

// pkill sends SIGTERM which skips applicationWillTerminate; route it there
signal(SIGTERM, SIG_IGN)
let sigTerm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigTerm.setEventHandler { NSApp.terminate(nil) }
sigTerm.resume()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
