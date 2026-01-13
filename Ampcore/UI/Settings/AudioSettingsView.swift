import SwiftUI

struct AudioSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        Form {
            Section {
                Toggle("Gapless", isOn: $env.settings.gaplessEnabled)
                Toggle("ReplayGain", isOn: $env.settings.replayGainEnabled)

                ToggleDisclosureSliderRow(
                    title: "Crossfade",
                    isOn: $env.settings.crossfadeEnabled,
                    value: $env.settings.crossfadeSeconds,
                    range: 1...12,
                    step: 0.5,
                    format: { String(format: "%.1fs", $0) }
                )

                ToggleDisclosureSliderRow(
                    title: "Fade Play/Pause/Stop",
                    isOn: $env.settings.fadeTransportEnabled,
                    value: $env.settings.fadeTransportSeconds,
                    range: 0.05...2.00,
                    step: 0.05,
                    format: { String(format: "%.2fs", $0) }
                )

                ToggleDisclosureSliderRow(
                    title: "Fade on Seek",
                    isOn: $env.settings.fadeSeekEnabled,
                    value: $env.settings.fadeSeekSeconds,
                    range: 0.02...0.50,
                    step: 0.01,
                    format: { String(format: "%.2fs", $0) }
                )
            }

            Section {
                NavigationLink {
                    EQView()
                } label: {
                    Label("EQ", systemImage: "slider.horizontal.3")
                }
            }
        }
        .navigationTitle("Audio")
    }
}

private struct ToggleDisclosureSliderRow: View {
    let title: String
    @Binding var isOn: Bool
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    @State private var expanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(title)
                Spacer(minLength: 8)

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        expanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)

                Toggle("", isOn: $isOn)
                    .labelsHidden()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.22)) {
                    expanded.toggle()
                }
            }

            if expanded {
                HStack(spacing: 12) {
                    Slider(value: $value, in: range, step: step)
                        .disabled(!isOn)

                    Text(format(value))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .trailing)
                        .opacity(isOn ? 1 : 0.35)
                }
                .padding(.top, 8)
                .opacity(isOn ? 1 : 0.35)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
