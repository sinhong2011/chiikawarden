import AppKit
import SwiftUI
import SSHAgent

/// The decision for one SSH signature: which app asked, which key, and how long to allow it.
struct SSHApprovalCard: View {
    var prompt: SSHPrompt
    var leadsWithUntilLock: Bool
    var choose: (SSHChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(prompt.displayName) wants to sign")
                        .font(.system(size: 14, weight: .semibold))
                    Text("via \(prompt.via) · \(prompt.keyName)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let path = prompt.path {
                Text(verbatim: path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if prompt.waitingCount > 1 {
                Text("^[\(prompt.waitingCount) signatures in this request](inflect: true)")
                    .font(.system(size: 12, weight: .medium))
            }
            Text("This signs one SSH operation. The private key stays in your vault.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if leadsWithUntilLock {
                Text("This app has asked to sign before.")
                    .font(.system(size: 12, weight: .medium))
            }
            Text("macOS will ask for Touch ID or your Mac login password. That password stays with macOS.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .background(Color.menuWash)
    }

    private var icon: some View {
        Group {
            if let path = prompt.appPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 8) {
            if leadsWithUntilLock {
                Button("Trust Until Lock") { choose(.allow(.untilLock)) }
                    .buttonStyle(.appPrimarySmall)
                    .keyboardShortcut(.defaultAction)
                HStack(spacing: 8) {
                    Button("Allow Once") { choose(.allow(.once)) }.buttonStyle(.appSecondarySmall)
                    Button("Allow for 10 Minutes") { choose(.allow(.tenMinutes)) }.buttonStyle(.appSecondarySmall)
                }
            } else {
                Button("Allow Once") { choose(.allow(.once)) }
                    .buttonStyle(.appPrimarySmall)
                    .keyboardShortcut(.defaultAction)
                HStack(spacing: 8) {
                    Button("Allow for 10 Minutes") { choose(.allow(.tenMinutes)) }.buttonStyle(.appSecondarySmall)
                    Button("Trust Until Lock") { choose(.allow(.untilLock)) }.buttonStyle(.appSecondarySmall)
                }
            }
            Button("Deny") { choose(.deny) }
                .buttonStyle(.appSecondarySmall)
                .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Floating panel for the card. Closing it leaves the request waiting; the menu bar can still answer.
@MainActor
final class SSHApprovalPanel: NSObject, NSWindowDelegate {
    static let shared = SSHApprovalPanel()

    private var panel: NSPanel?
    private var front: NSRunningApplication?
    private var hiddenByUser = false
    private var shownID: UUID?

    func sync(_ prompt: SSHPrompt, service: SSHAgentService) {
        if shownID != prompt.id {
            hiddenByUser = false
            shownID = prompt.id
        }
        install(prompt, service: service)
        guard !hiddenByUser else { return }
        orderFront()
    }

    func reopen(service: SSHAgentService) {
        hiddenByUser = false
        guard let pending = service.pending else { return }
        install(pending, service: service)
        orderFront()
    }

    func close(restoreFocus: Bool) {
        panel?.orderOut(nil)
        shownID = nil
        hiddenByUser = false
        if restoreFocus { front?.activate(); front = nil }
    }

    private func install(_ prompt: SSHPrompt, service: SSHAgentService) {
        let card = SSHApprovalCard(prompt: prompt, leadsWithUntilLock: service.pendingLeadsWithUntilLock) { [weak service] choice in
            service?.choose(choice)
        }
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 320),
                                styleMask: [.titled, .closable, .fullSizeContentView],
                                backing: .buffered, defer: false)
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.delegate = self
            panel.backgroundColor = .clear
            self.panel = panel
        }
        panel?.contentView = NSHostingView(rootView: card)
        panel?.setContentSize(NSSize(width: 380, height: panel?.contentView?.fittingSize.height ?? 320))
    }

    private func orderFront() {
        guard let panel else { return }
        if front == nil { front = NSWorkspace.shared.frontmostApplication }
        if !panel.isVisible { panel.center() }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hiddenByUser = true
        return true
    }
}
