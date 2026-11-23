import SwiftUI

/// Real-time AI Assistant Response viewer with structured Markdown rendering, fenced code blocks
/// with 1-click copy, conversation turn history pager (`‹ 1/N ›`), on-demand full transcript
/// hydration, and silky 120Hz zero-gravity optical rack-focus streaming animation.
public struct ResponseTelemetryTabView: View {
    public var store: AntigravityTelemetryStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedIndex: Int = 0
    @State private var loadedFullReplies: [Int: String] = [:]
    @State private var loadingStepIndex: Int?
    @State private var copiedReplyStepIndex: Int?
    @State private var copiedCodeBlockID: String?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var liveCaretPulse: Bool = false

    public init(store: AntigravityTelemetryStore) {
        self.store = store
    }

    private var availableResponses: [AssistantResponseSnapshot] {
        store.responses
    }

    private var activeResponse: AssistantResponseSnapshot? {
        guard !availableResponses.isEmpty else { return nil }
        let idx = min(max(0, selectedIndex), availableResponses.count - 1)
        return availableResponses[idx]
    }

    public var body: some View {
        Group {
            if let response = activeResponse {
                responseCanvas(for: response)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: store.responses.first?.stepIndex) { _, _ in
            // Auto-follow newest AI answer as it arrives in real time
            if reduceMotion {
                selectedIndex = 0
            } else {
                withAnimation(.spring(duration: 0.36, bounce: 0.10)) {
                    selectedIndex = 0
                }
            }
        }
        .onDisappear {
            feedbackTask?.cancel()
        }
    }

    // MARK: - Editorial Response Canvas

    private func responseCanvas(for response: AssistantResponseSnapshot) -> some View {
        let resolvedText = (loadedFullReplies[response.stepIndex] ?? response.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let blocks = MarkdownResponseParser.parse(resolvedText)
        let needsFullLoad = response.isTruncated
            && !response.isFullTextLoaded
            && loadedFullReplies[response.stepIndex] == nil
        let isLoadingFull = loadingStepIndex == response.stepIndex
        let isCopied = copiedReplyStepIndex == response.stepIndex

        return VStack(alignment: .leading, spacing: 0) {
            // Whisper-clean top context strip: User prompt quote + Turn pager + Copy
            HStack(spacing: 6) {
                if let prompt = response.promptPreview, !prompt.isEmpty {
                    HStack(spacing: 4.5) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.32))

                        Text(prompt)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.46))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else {
                    HStack(spacing: 5) {
                        NotchSemanticDot(
                            color: response.isStreaming ? GravPalette.thinking : GravPalette.emerald,
                            size: 5,
                            isPulsing: response.isStreaming && !store.isPaused
                        )
                        Text(response.isStreaming ? "Responding" : "Assistant Reply")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.76))
                    }
                }

                Spacer(minLength: 8)

                if availableResponses.count > 1 {
                    HStack(spacing: 2) {
                        Button {
                            stepReply(by: 1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(selectedIndex < availableResponses.count - 1 ? 0.62 : 0.20))
                                .frame(width: 16, height: 18)
                        }
                        .buttonStyle(NotchChromeButtonStyle(cornerRadius: 4.5))
                        .disabled(selectedIndex >= availableResponses.count - 1)
                        .help("Older reply")

                        Text("\(selectedIndex + 1)/\(availableResponses.count)")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.38))

                        Button {
                            stepReply(by: -1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(selectedIndex > 0 ? 0.62 : 0.20))
                                .frame(width: 16, height: 18)
                        }
                        .buttonStyle(NotchChromeButtonStyle(cornerRadius: 4.5))
                        .disabled(selectedIndex <= 0)
                        .help("Newer reply")
                    }
                }

                Button {
                    copyReply(resolvedText, stepIndex: response.stepIndex)
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isCopied ? GravPalette.emerald : Color.white.opacity(0.52))
                        .frame(width: 20, height: 18)
                }
                .buttonStyle(NotchChromeButtonStyle(isActive: isCopied, cornerRadius: 5))
                .help("Copy Reply (⌘C)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .padding(.horizontal, 10)

            // Smoothly streaming structured Markdown viewport
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                            MaterializingResponseBlock(
                                staggerIndex: min(index, 6),
                                reduceMotion: reduceMotion
                            ) {
                                blockView(block, stepIndex: response.stepIndex)
                            }
                        }

                        if response.isStreaming && !store.isPaused {
                            streamingOpticalCaret
                        }

                        if needsFullLoad {
                            HStack {
                                Button {
                                    loadFullReply(stepIndex: response.stepIndex)
                                } label: {
                                    HStack(spacing: 5) {
                                        if isLoadingFull {
                                            OpticalCommandSpinner(isActive: true, size: 8, tint: GravPalette.glacialCyan)
                                        } else {
                                            Image(systemName: "arrow.down.doc")
                                                .font(.system(size: 9.5, weight: .medium))
                                        }
                                        Text(isLoadingFull ? "Loading full reply…" : "Load full reply")
                                            .font(.system(size: 10.5, weight: .medium))
                                    }
                                    .foregroundStyle(GravPalette.glacialCyan)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3.5)
                                }
                                .buttonStyle(NotchChromeButtonStyle(cornerRadius: 5.5))
                                .disabled(isLoadingFull)

                                Spacer()
                            }
                            .padding(.top, 2)
                        }

                        Color.clear
                            .frame(height: 6)
                            .id("reply-stream-tail")
                    }
                    .padding(.horizontal, 11)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .id(response.stepIndex)
                }
                .mask(responseScrollMask)
                .onChange(of: resolvedText) { _, _ in
                    guard selectedIndex == 0 else { return }
                    if reduceMotion {
                        proxy.scrollTo("reply-stream-tail", anchor: .bottom)
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo("reply-stream-tail", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.038))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.03),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
        )
    }

    // MARK: - Block Rendering

    @ViewBuilder
    private func blockView(_ block: MarkdownResponseBlock, stepIndex: Int) -> some View {
        switch block.kind {
        case let .heading(text):
            Text(inlineMarkdown(text))
                .font(.system(size: 12.5, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.white.opacity(0.96))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

        case let .paragraph(text):
            Text(inlineMarkdown(text))
                .font(.system(size: 11.8, weight: .regular))
                .lineSpacing(3.5)
                .foregroundStyle(Color.white.opacity(0.84))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Circle()
                    .fill(GravPalette.glacialCyan.opacity(0.75))
                    .frame(width: 4, height: 4)
                    .offset(y: -1.5)

                Text(inlineMarkdown(text))
                    .font(.system(size: 11.8, weight: .regular))
                    .lineSpacing(3.2)
                    .foregroundStyle(Color.white.opacity(0.84))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case let .code(language, source):
            let blockKey = "\(stepIndex)-\(block.id)"
            let isCopied = copiedCodeBlockID == blockKey

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(language.isEmpty ? "code" : language)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.36))

                    Spacer()

                    Button {
                        copyCode(source, id: blockKey)
                    } label: {
                        HStack(spacing: 3.5) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 8.5, weight: .medium))
                            Text(isCopied ? "Copied" : "Copy")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundStyle(isCopied ? GravPalette.emerald : Color.white.opacity(0.56))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(NotchChromeButtonStyle(isActive: isCopied, cornerRadius: 4.5))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(source)
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .lineSpacing(2.5)
                        .foregroundStyle(Color.white.opacity(0.86))
                        .textSelection(.enabled)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .fill(Color.black.opacity(0.42))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
    }

    private var streamingOpticalCaret: some View {
        HStack(spacing: 6) {
            Capsule(style: .continuous)
                .fill(GravPalette.thinking)
                .frame(width: 2.2, height: 12)
                .opacity(reduceMotion ? 0.9 : (liveCaretPulse ? 0.95 : 0.25))
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                        liveCaretPulse = true
                    }
                }
                .onDisappear {
                    liveCaretPulse = false
                }

            Text("Streaming response…")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.38))
        }
        .padding(.top, 2)
    }

    private var responseScrollMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.03),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Actions & Markdown Helper

    private func inlineMarkdown(_ text: String) -> AttributedString {
        MarkdownResponseParser.cachedInlineMarkdown(text)
    }

    private func stepReply(by delta: Int) {
        let maxIdx = max(0, availableResponses.count - 1)
        let target = min(max(0, selectedIndex + delta), maxIdx)
        guard target != selectedIndex else { return }
        GravOnboardingWelcomeAudio.shared.playTabSwitch()
        if reduceMotion {
            selectedIndex = target
        } else {
            withAnimation(.spring(duration: 0.34, bounce: 0.10)) {
                selectedIndex = target
            }
        }
    }

    private func loadFullReply(stepIndex: Int) {
        guard loadingStepIndex != stepIndex else { return }
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        loadingStepIndex = stepIndex
        Task { @MainActor in
            let step = await store.loadFullStep(stepIndex: stepIndex)
            if let fullContent = step?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
               !fullContent.isEmpty
            {
                loadedFullReplies[stepIndex] = fullContent
            }
            if loadingStepIndex == stepIndex {
                loadingStepIndex = nil
            }
        }
    }

    private func copyReply(_ text: String, stepIndex: Int) {
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        NotchTelemetryHelpers.copyToPasteboard(text)
        copiedReplyStepIndex = stepIndex
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.3))
            guard !Task.isCancelled else { return }
            if copiedReplyStepIndex == stepIndex {
                copiedReplyStepIndex = nil
            }
        }
    }

    private func copyCode(_ code: String, id: String) {
        GravOnboardingWelcomeAudio.shared.playButtonTap()
        NotchTelemetryHelpers.copyToPasteboard(code)
        copiedCodeBlockID = id
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.3))
            guard !Task.isCancelled else { return }
            if copiedCodeBlockID == id {
                copiedCodeBlockID = nil
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.30))

            Text("No Assistant Replies Yet")
                .font(.system(size: 12, weight: .medium))
                .tracking(-0.15)
                .foregroundStyle(Color.white.opacity(0.76))

            Text("Antigravity's real-time responses and code snippets will stream here.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.38))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Zero-Gravity Optical Rack-Focus Block Reveal (120Hz)

private struct MaterializingResponseBlock<Content: View>: View {
    let staggerIndex: Int
    let reduceMotion: Bool
    @ViewBuilder let content: () -> Content

    @State private var appeared: Bool = false

    var body: some View {
        content()
            .opacity(reduceMotion || appeared ? 1.0 : 0.0)
            .blur(radius: reduceMotion || appeared ? 0 : 4.5)
            .offset(y: reduceMotion || appeared ? 0 : 6)
            .onAppear {
                guard !appeared else { return }
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(
                        .timingCurve(0.18, 1.0, 0.32, 1.0, duration: 0.36)
                            .delay(Double(staggerIndex) * 0.028)
                    ) {
                        appeared = true
                    }
                }
            }
    }
}

// MARK: - Lightweight Markdown Block Parser

private struct MarkdownResponseBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case heading(String)
        case paragraph(String)
        case bullet(String)
        case code(language: String, source: String)
    }

    let id: String
    let kind: Kind
}

private enum MarkdownResponseParser {
    @MainActor private static var blockCache: [String: [MarkdownResponseBlock]] = [:]
    @MainActor private static var blockCacheOrder: [String] = []
    private static let maxBlockCacheEntries = 32

    @MainActor private static var inlineCache: [String: AttributedString] = [:]
    @MainActor private static var inlineCacheOrder: [String] = []
    private static let maxInlineCacheEntries = 160

    @MainActor
    static func cachedInlineMarkdown(_ text: String) -> AttributedString {
        if let cached = inlineCache[text] {
            return cached
        }
        let parsed: AttributedString
        if let md = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            parsed = md
        } else {
            parsed = AttributedString(text)
        }
        inlineCache[text] = parsed
        inlineCacheOrder.append(text)
        if inlineCacheOrder.count > maxInlineCacheEntries {
            let evicted = inlineCacheOrder.removeFirst()
            inlineCache.removeValue(forKey: evicted)
        }
        return parsed
    }

    @MainActor
    static func parse(_ input: String) -> [MarkdownResponseBlock] {
        guard !input.isEmpty else { return [] }
        if let cached = blockCache[input] {
            return cached
        }
        let parsed = parseUncached(input)
        blockCache[input] = parsed
        blockCacheOrder.append(input)
        if blockCacheOrder.count > maxBlockCacheEntries {
            let evicted = blockCacheOrder.removeFirst()
            blockCache.removeValue(forKey: evicted)
        }
        return parsed
    }

    private static func parseUncached(_ input: String) -> [MarkdownResponseBlock] {
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownResponseBlock] = []
        var paragraphBuffer: [String] = []
        var inCodeFence = false
        var codeLanguage = ""
        var codeLines: [String] = []
        var blockCounter = 0

        func flushParagraph() {
            let joined = paragraphBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(MarkdownResponseBlock(id: "p-\(blockCounter)", kind: .paragraph(joined)))
                blockCounter += 1
            }
            paragraphBuffer.removeAll()
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeFence {
                    let source = codeLines.joined(separator: "\n")
                    blocks.append(MarkdownResponseBlock(id: "c-\(blockCounter)", kind: .code(language: codeLanguage, source: source)))
                    blockCounter += 1
                    codeLines.removeAll()
                    codeLanguage = ""
                    inCodeFence = false
                } else {
                    flushParagraph()
                    inCodeFence = true
                    codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            if inCodeFence {
                codeLines.append(rawLine)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                continue
            }

            if trimmed.hasPrefix("#") {
                flushParagraph()
                let headingText = trimmed.drop(while: { $0 == "#" || $0 == " " })
                if !headingText.isEmpty {
                    blocks.append(MarkdownResponseBlock(id: "h-\(blockCounter)", kind: .heading(String(headingText))))
                    blockCounter += 1
                }
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                let bulletText = String(trimmed.dropFirst(2))
                blocks.append(MarkdownResponseBlock(id: "b-\(blockCounter)", kind: .bullet(bulletText)))
                blockCounter += 1
                continue
            }

            paragraphBuffer.append(rawLine)
        }

        if inCodeFence && !codeLines.isEmpty {
            blocks.append(MarkdownResponseBlock(id: "c-\(blockCounter)", kind: .code(language: codeLanguage, source: codeLines.joined(separator: "\n"))))
        } else {
            flushParagraph()
        }

        return blocks
    }
}
