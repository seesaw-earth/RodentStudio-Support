import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Read-only inspection: old project.json is never written or migrated implicitly.
struct LegacyProjectInspector: View {
    @State private var fileName = L("No legacy project selected", "未选择旧项目")
    @State private var projectName = ""
    @State private var experiments: [String] = []
    @State private var animals = 0
    @State private var recordings = 0
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Legacy Project Inspector", "旧项目查看器")).font(.largeTitle.bold())
            Text(L("Read-only preview of a 0.2.0 .rodentproj/project.json. No files are modified.", "只读预览 0.2.0 的 .rodentproj/project.json，不修改任何文件。"))
                .foregroundStyle(.secondary)
            Button(L("Open project.json…", "打开 project.json…")) { open() }
            Text(fileName).font(.callout).foregroundStyle(.secondary)
            if let e = errorMessage { Text(e).foregroundStyle(.red) }
            if !projectName.isEmpty {
                Text(projectName).font(.title2.bold())
                Text(L("\(animals) animals · \(recordings) recordings", "\(animals) 只动物 · \(recordings) 段记录"))
                ForEach(experiments, id: \.self) { name in Text("• \(name)") }
            }
        }
    }

    private func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = L("Select the project.json inside a .rodentproj folder", "选择 .rodentproj 文件夹中的 project.json")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "LegacyImport", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Not a Rodent Desktop / RodentStudio JSON object"])
            }
            projectName = dictionary["name"] as? String ?? "Untitled"
            let exps = dictionary["experiments"] as? [[String: Any]] ?? []
            experiments = exps.map { "\($0["name"] as? String ?? "Experiment") — \($0["assay_id"] as? String ?? "unknown")" }
            animals = (dictionary["animals"] as? [Any])?.count ?? 0
            recordings = (dictionary["recordings"] as? [Any])?.count ?? 0
            fileName = url.path
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
