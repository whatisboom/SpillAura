import SwiftUI
import SpillAuraCore

// MARK: - CodableColor ↔ SwiftUI.Color bridge (macOS)

private extension CodableColor {
    func toColor() -> Color {
        Color(red: red, green: green, blue: blue)
    }

    init(color: Color) {
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        self.init(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent)
    }
}

// MARK: - Sheet

struct AuraEditorSheet: View {
    @EnvironmentObject private var auraLibrary: AuraLibrary
    @Environment(\.dismiss) private var dismiss

    private let existingID: UUID?

    @State private var name: String
    @State private var colors: [CodableColor]
    @State private var speed: Double
    @State private var pattern: AuraPattern
    @State private var channelOffset: Double

    /// Pass an existing `Aura` to edit it, or `nil` to create a new one.
    init(aura: Aura? = nil) {
        existingID = aura?.id
        _name = State(initialValue: aura?.name ?? "")
        _colors = State(initialValue: aura?.palette ?? [
            CodableColor(red: 1.00, green: 0.20, blue: 0.60),
            CodableColor(red: 0.20, green: 0.40, blue: 1.00),
        ])
        _speed = State(initialValue: aura?.speed ?? 0.25)
        _pattern = State(initialValue: aura?.pattern ?? .cycle)
        _channelOffset = State(initialValue: aura?.channelOffset ?? 0.2)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && colors.count >= 2
    }

    private var sheetTitle: String {
        if existingID != nil {
            return name.isEmpty ? "Edit Aura" : name
        }
        return "New Aura"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Form {
                Section("Name") {
                    TextField("Aura name", text: $name)
                }

                Section {
                    ForEach(colors.indices, id: \.self) { idx in
                        colorRow(index: idx)
                    }
                    .onMove { colors.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { colors.remove(atOffsets: $0) }

                    if colors.count < 8 {
                        Button {
                            colors.append(CodableColor(red: 1, green: 1, blue: 1))
                        } label: {
                            Label("Add Color", systemImage: "plus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                } header: {
                    Text("Colors")
                } footer: {
                    Text("Drag rows to reorder  ·  2–8 colors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Behavior") {
                    LabeledContent("Speed") {
                        Slider(value: $speed, in: 0.01...1.0)
                            .frame(minWidth: 160)
                    }

                    Picker("Pattern", selection: $pattern) {
                        Text("Cycle").tag(AuraPattern.cycle)
                        Text("Bounce").tag(AuraPattern.bounce)
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Channel Offset") {
                        Slider(value: $channelOffset, in: 0...1)
                            .frame(minWidth: 160)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 440, height: 520)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
            Spacer()
            Text(sheetTitle)
                .fontWeight(.semibold)
            Spacer()
            Button("Save") { save() }
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func colorRow(index: Int) -> some View {
        HStack(spacing: 12) {
            ColorPicker(
                "",
                selection: Binding(
                    get: { colors[index].toColor() },
                    set: { colors[index] = CodableColor(color: $0) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()

            Rectangle()
                .fill(colors[index].toColor())
                .frame(height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Spacer()

            if colors.count > 2 {
                Button {
                    colors.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove this color")
            }
        }
    }

    // MARK: - Actions

    private func save() {
        let aura = Aura(
            id: existingID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            type: .dynamic,
            palette: colors,
            speed: speed,
            pattern: pattern,
            channelOffset: channelOffset
        )
        auraLibrary.save(aura)
        dismiss()
    }
}
