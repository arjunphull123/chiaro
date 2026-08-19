import SwiftUI

/// RGB histogram on a solid plate (ADR 0006: the one opaque surface in the rail).
struct HistogramView: View {
    let data: HistogramData

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Theme.panel)
            if !data.isEmpty {
                Canvas { ctx, size in
                    for (channel, color) in [
                        (data.red, Color(red: 1, green: 0.35, blue: 0.3)),
                        (data.green, Color(red: 0.4, green: 1, blue: 0.45)),
                        (data.blue, Color(red: 0.4, green: 0.6, blue: 1)),
                    ] {
                        var path = Path()
                        let step = size.width / CGFloat(channel.count - 1)
                        path.move(to: CGPoint(x: 0, y: size.height))
                        for (i, v) in channel.enumerated() {
                            path.addLine(to: CGPoint(
                                x: CGFloat(i) * step,
                                y: size.height - CGFloat(v) * (size.height - 4)
                            ))
                        }
                        path.addLine(to: CGPoint(x: size.width, y: size.height))
                        path.closeSubpath()
                        ctx.fill(path, with: .color(color.opacity(0.45)))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .blendMode(.screen)
            }
        }
        .frame(height: 62)
        .overlay(alignment: .bottomLeading) {
            Text("SHADOWS")
                .font(Theme.mono(7)).kerning(1).foregroundStyle(Theme.ink3)
                .padding(.leading, 7).padding(.bottom, 4)
        }
        .overlay(alignment: .bottomTrailing) {
            Text("HIGHLIGHTS")
                .font(Theme.mono(7)).kerning(1).foregroundStyle(Theme.ink3)
                .padding(.trailing, 7).padding(.bottom, 4)
        }
        .help("The photo's tones, dark to bright. A pile against the left edge means crushed shadows; against the right, blown highlights.")
    }
}
