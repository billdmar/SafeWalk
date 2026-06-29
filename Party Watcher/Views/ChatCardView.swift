import SwiftUI

/// The check-in chat card: the scrolling transcript, a "typing" indicator, the
/// deterministic quick-reply row, and the message input bar.
struct ChatCardView: View {
    @ObservedObject var vm: SafetyWatcherViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives keyboard focus so it can be dismissed after a message is sent.
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Check-in chat", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.headline)
                .foregroundColor(Theme.burntOrange)
            transcript
            quickReplyRow
            inputBar
        }
        .card()
    }

    private var transcript: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(vm.messages) { msg in
                        ChatBubble(message: msg.text, isUser: msg.isUser)
                            .id(msg.id)
                            .transition(reduceMotion
                                        ? .opacity
                                        : .opacity.combined(with: .move(edge: .bottom)))
                    }
                    if vm.isLoadingResponse {
                        TypingIndicatorView()
                            .id("typing")
                    }
                }
                .padding(.vertical, 4)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: vm.messages.count)
                .onChange(of: vm.messages.count) {
                    if let last = vm.messages.last {
                        withAnimation { scrollProxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .frame(height: 240)
            .accessibilityIdentifier("chatTranscript")
        }
    }

    /// A horizontal row of deterministic quick-reply buttons. Tapping one posts
    /// a canned exchange (and may confirm safety or escalate) without any network
    /// call — the chat stays conversational even offline.
    private var quickReplyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QuickReplies.all) { reply in
                    Button(action: { vm.tapQuickReply(reply) }) {
                        Text(reply.label)
                            .font(.subheadline).fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(reply.effect == .escalate
                                               ? Theme.alert.opacity(0.15)
                                               : Theme.burntOrange.opacity(0.12))
                            )
                            .foregroundColor(reply.effect == .escalate ? Theme.alert : Theme.burntOrange)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint(reply.effect == .escalate
                                       ? "Sends a distress message and escalates immediately."
                                       : "Sends a quick reply to the companion.")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Type your reply…", text: $vm.userInput)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(minHeight: 44)
                .autocapitalization(.sentences)
                .disableAutocorrection(true)
                .submitLabel(.send)
                .focused($inputFocused)
                .onSubmit(send)
                .accessibilityIdentifier("chatInput")
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(vm.inputIsEmpty ? Color.gray.opacity(0.4) : Theme.burntOrange)
            }
            .disabled(vm.inputIsEmpty)
            .buttonStyle(.pressable)
            .accessibilityLabel("Send reply")
            .accessibilityIdentifier("sendButton")
        }
    }

    /// Sends the current message and dismisses the keyboard, so the transcript
    /// isn't left hidden behind it after a reply.
    private func send() {
        guard !vm.inputIsEmpty else { return }
        vm.sendMessage()
        inputFocused = false
    }
}
