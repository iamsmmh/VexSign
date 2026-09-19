import SwiftUI
import UniformTypeIdentifiers

struct RepositoryBuilderView: View {
    @StateObject private var model = RepositoryBuilderViewModel()
    @State private var importing = false
    @State private var editing: RepositoryDocument?
    @State private var remoteURL = ""
    @State private var format: RepositoryFormat = .altStore
    var body: some View {
        List {
            Section {
                Button("Create Repository") { editing = RepositoryDocument() }
                Button("Import JSON File") { importing = true }
            }
            Section("Import HTTPS Repository") {
                TextField("https://example.com/source.json", text: $remoteURL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("Format", selection: $format) { ForEach(RepositoryFormat.allCases) { Text($0.rawValue).tag($0) } }
                Button("Import URL") { Task { await model.importURL(remoteURL, format: format) } }.disabled(remoteURL.isEmpty)
            }
            Section("Your Repositories") {
                ForEach(model.documents) { doc in
                    Button { editing = doc } label: {
                        VStack(alignment: .leading) { Text(doc.name); Text("\(doc.apps.count) apps · \(doc.format.rawValue)").font(.caption).foregroundStyle(.secondary) }
                    }
                }.onDelete { offsets in Task { await model.delete(offsets) } }
            }
            if let error = model.error { Section("Error") { Text(error).foregroundStyle(.red) } }
        }
        .disabled(model.busy)
        .navigationTitle("Repository Builder")
        .task { await model.load() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): Task { await model.importFile(url) }
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .sheet(item: $editing) { doc in
            NavigationStack { RepositoryEditorView(document: doc) { try await model.save($0) } }
        }
    }
}
