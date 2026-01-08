import SwiftUI

struct SearchView: View {
    @State private var query: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    if query.isEmpty {
                        ContentUnavailableView("Search", systemImage: "magnifyingglass", description: Text("Search your library."))
                    } else {
                        Text("Results for: \(query)")
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        }
    }
}
