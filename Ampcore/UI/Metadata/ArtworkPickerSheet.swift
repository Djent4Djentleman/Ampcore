import SwiftUI

struct ArtworkPickerSheet: View {
    let track: TrackViewModel
    @State private var query: String = ""
    @State private var items: [ArtworkCandidate] = []
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss
    
    private let service = ArtworkSearchService()
    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 10)]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Artist / Album / Title", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if isLoading { ProgressView().scaleEffect(0.9) }
                    Button("Search") { Task { await runSearch() } }
                        .buttonStyle(.bordered)
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal)
                
                ScrollView {
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(items) { item in
                            AsyncImage(url: item.imageURL) { phase in
                                switch phase {
                                case .empty:
                                    RoundedRectangle(cornerRadius: 16).fill(.thinMaterial).frame(height: 110)
                                case .success(let img):
                                    img.resizable().scaledToFill()
                                        .frame(height: 110)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                case .failure:
                                    RoundedRectangle(cornerRadius: 16).fill(.thinMaterial).frame(height: 110)
                                        .overlay(Image(systemName: "xmark.octagon").opacity(0.6))
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .onTapGesture {
                                // MVP: просто закрываем (вшивка в файл — позже через TagLib)
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 14)
                }
            }
            .navigationTitle("Artwork")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            query = [track.artist, track.album, track.title].compactMap { $0 }.joined(separator: " ")
            await runSearch()
        }
    }
    
    private func runSearch() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await service.search(artist: track.artist, album: track.album, title: track.title)
        } catch {
            items = []
        }
    }
}
