import SwiftUI

struct AnimationPanelView: View {
    let frameCount: Int
    let currentFrameIndex: Int
    let isPlaying: Bool
    let animations: [VoxelAnimation]
    let selectedAnimationIndex: Int?
    let onTogglePlayback: () -> Void
    let onSelectFrame: (Int) -> Void
    let onAddFrame: () -> Void
    let onDeleteFrame: () -> Void
    let onDuplicateFrame: () -> Void
    let onAddAnimation: () -> Void
    let onDeleteAnimation: () -> Void
    let onDuplicateAnimation: () -> Void
    let onSelectAnimation: (Int?) -> Void
    let onRenameAnimation: (String) -> Void
    let onSetAnimationFPS: (Int) -> Void
    let onAppendCurrentFrameToAnimation: () -> Void
    let onSelectAnimationSequenceFrame: (Int) -> Void
    let onRemoveAnimationSequenceFrame: (Int) -> Void

    @State private var animationNameDraft = ""
    @State private var hoveredDescription: String?

    var body: some View {
        EditorSection(title: "Animation") {
            HStack(spacing: 8) {
                panelButton("Add", systemImage: "plus", help: "Append a new empty frame at the end of the frame list.", action: onAddFrame)
                panelButton("Duplicate", systemImage: "plus.square.on.square", help: "Duplicate the current frame to the end of the frame list.", action: onDuplicateFrame)
                panelButton("Delete", systemImage: "trash", help: "Delete the current frame.", action: onDeleteFrame)
                    .disabled(frameCount <= 1)
            }

            Stepper(
                "Frame \(currentFrameIndex + 1) of \(frameCount)",
                value: Binding(
                    get: { currentFrameIndex },
                    set: { onSelectFrame($0) }
                ),
                in: 0...max(frameCount - 1, 0)
            )

            if frameCount > 1 {
                Slider(
                    value: Binding(
                        get: { Double(currentFrameIndex) },
                        set: { onSelectFrame(Int($0.rounded())) }
                    ),
                    in: 0...Double(frameCount - 1),
                    step: 1
                )
            }

            Divider()

            HStack(spacing: 8) {
                panelButton("New Clip", systemImage: "film.stack", help: "Create a new animation clip using the current frame as its first entry.", action: onAddAnimation)
                panelButton("Duplicate", systemImage: "doc.on.doc", help: "Duplicate the selected animation clip.", action: onDuplicateAnimation)
                    .disabled(selectedAnimationIndex == nil)
                panelButton("Delete", systemImage: "trash", help: "Delete the selected animation clip.", action: onDeleteAnimation)
                    .disabled(selectedAnimationIndex == nil)
            }

            Picker("Clip", selection: Binding(
                get: { selectedAnimationIndex ?? -1 },
                set: { onSelectAnimation($0 >= 0 ? $0 : nil) }
            )) {
                Text("None").tag(-1)
                ForEach(Array(animations.enumerated()), id: \.offset) { index, animation in
                    Text(animation.name).tag(index)
                }
            }
            .labelsHidden()

            if let selectedAnimationIndex, animations.indices.contains(selectedAnimationIndex) {
                let animation = animations[selectedAnimationIndex]

                TextField("Animation Name", text: Binding(
                    get: {
                        if animationNameDraft.isEmpty || animationNameDraft == animations[selectedAnimationIndex].name {
                            return animations[selectedAnimationIndex].name
                        }
                        return animationNameDraft
                    },
                    set: { newValue in
                        animationNameDraft = newValue
                        onRenameAnimation(newValue)
                    }
                ))
                .textFieldStyle(.roundedBorder)

                Stepper(
                    "FPS: \(animation.fps)",
                    value: Binding(
                        get: { animation.fps },
                        set: { onSetAnimationFPS($0) }
                    ),
                    in: 1...60
                )

                HStack(spacing: 8) {
                    panelButton(isPlaying ? "Pause Clip" : "Play Clip", systemImage: isPlaying ? "pause.fill" : "play.fill", help: isPlaying ? "Pause playback of the selected clip." : "Play the selected clip at its configured FPS.", action: onTogglePlayback)
                }

                HStack(spacing: 8) {
                    panelButton("Add Current Frame", systemImage: "plus.circle", help: "Append the current frame to the selected clip sequence.", action: onAppendCurrentFrameToAnimation)
                        .disabled(animation.frameIndices.count >= VoxelAnimation.maxFrameIndices)
                }

                if animation.frameIndices.isEmpty {
                    Text("No frames in this clip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(Array(animation.frameIndices.enumerated()), id: \.offset) { sequenceIndex, frameIndex in
                            HStack(spacing: 4) {
                                Button("F\(frameIndex + 1)") {
                                    onSelectAnimationSequenceFrame(sequenceIndex)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .help("Jump to frame \(frameIndex + 1) from this clip entry.")
                                .onHover { isHovering in
                                    let help = "Jump to frame \(frameIndex + 1) from clip position \(sequenceIndex + 1)."
                                    hoveredDescription = isHovering ? help : hoveredDescription == help ? nil : hoveredDescription
                                }

                                Button {
                                    onRemoveAnimationSequenceFrame(sequenceIndex)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .help("Remove this frame entry from the selected clip.")
                                .onHover { isHovering in
                                    let help = "Remove clip position \(sequenceIndex + 1) from the selected animation."
                                    hoveredDescription = isHovering ? help : hoveredDescription == help ? nil : hoveredDescription
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                        }
                    }
                }
            } else {
                Text("Select a clip to edit its frame sequence and FPS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            PanelHelpText(text: hoveredDescription ?? defaultHelpText)
        }
        .onChange(of: selectedAnimationIndex) { _, _ in
            animationNameDraft = ""
        }
    }

    private var defaultHelpText: String {
        if selectedAnimationIndex != nil {
            return "Manage frames, clips, and playback for the current animation."
        }
        return "Manage frame creation and animation clips."
    }

    private func panelButton(_ title: String, systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .help(help)
        .onHover { isHovering in
            hoveredDescription = isHovering ? help : hoveredDescription == help ? nil : hoveredDescription
        }
    }
}

private struct FlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > maxWidth {
                currentX = 0
                currentY += rowHeight + verticalSpacing
                rowHeight = 0
            }
            usedWidth = max(usedWidth, currentX + size.width)
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + horizontalSpacing
        }

        return CGSize(width: usedWidth, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + verticalSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            currentX += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
