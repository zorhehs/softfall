import SwiftUI

/// Small pieces shared by the window and the menu bar's quick menu. They live
/// here rather than inside one view so that neither owns the other.

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.4)
    }
}

/// A row in the window's scene list. The window has room to say what each
/// scene *is*, which three cramped tiles in a popover never did.
struct SceneRow: View {
    let scene: Scene
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: scene.symbol)
                    .font(.system(size: 15, weight: .light))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(scene.title)
                        .font(.system(size: 12.5, weight: .medium))
                    Text(scene.blurb)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SwitchTile: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: isOn ? .medium : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            )
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(isOn ? "\(title) is on" : "\(title) is off")
    }
}

/// An icon, a fixed-width caption and a slider. Used often enough in the
/// settings column that three copies of the same HStack was worse.
struct SliderRow: View {
    let title: String
    let symbol: String
    let range: ClosedRange<Double>
    @Binding var value: Double
    var trailing: String?

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 15)
            Text(title)
                .font(.system(size: 11.5))
                .frame(width: 72, alignment: .leading)
            Slider(value: $value, in: range)
                .controlSize(.small)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}
