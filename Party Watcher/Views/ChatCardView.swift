import SwiftUI

/// The check-in chat card: the scrolling transcript, a "typing" indicator, the
/// deterministic quick-reply row, and the message input bar.
struct ChatCardView: View {
    @ObservedObject var vm: SafetyWatcherViewModel

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
                    }
                    if vm.isLoadingResponse {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Companion is typing…")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .id("typing")
                    }
                }
                .padding(.vertical, 4)
                .onChange(of: vm.messages.count) {
                    if let last = vm.messages.last {
                        withAnimation { scrollProxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .frame(height: 240)
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
                .onSubmit { if !vm.inputIsEmpty { vm.sendMessage() } }
            Button(action: { vm.sendMessage() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(vm.inputIsEmpty ? Color.gray.opacity(0.4) : Theme.burntOrange)
            }
            .disabled(vm.inputIsEmpty)
            .accessibilityLabel("Send reply")
        }
    }
}
