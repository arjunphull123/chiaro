import SwiftUI

/// Session filmstrip: a Liquid Glass pill floating over the canvas.
struct FilmstripView: View {
    let photos: [Photo]
    let current: Photo
    let select: (Photo) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos) { photo in
                        thumb(photo)
                            .id(photo.url)
                            .onTapGesture { select(photo) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .frame(maxWidth: 560)
            .chiaroGlass(cornerRadius: 15)
            .onAppear { proxy.scrollTo(current.url, anchor: .center) }
            .onChange(of: current.url) { proxy.scrollTo(current.url, anchor: .center) }
        }
    }

    private func thumb(_ photo: Photo) -> some View {
        let selected = photo.url == current.url
        return ZStack(alignment: .bottomTrailing) {
            Group {
                if let cg = photo.thumbnail {
                    Image(cg, scale: 1, label: Text(photo.name))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Theme.panel
                }
            }
            .frame(width: 58, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .opacity(selected ? 1 : 0.72)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(selected ? Theme.amber : .clear, lineWidth: 1.5)
            )
            if photo.hasEdits {
                Circle().fill(Theme.amber)
                    .frame(width: 5, height: 5)
                    .offset(x: -4, y: -4)
            }
        }
    }
}
