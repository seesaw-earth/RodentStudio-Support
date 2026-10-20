import SwiftUI
import AppKit
import PhotosUI
import UniformTypeIdentifiers

/// A movie picked from Photos, copied into the app's temporary directory.
struct TSTPickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "-" + received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return Self(url: dst)
        }
    }
}

/// The standard macOS open panel for one TST recording (the same panel the other tasks use).
enum TSTVideoPicker {
    @MainActor
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = L("Choose one TST recording (several mice hanging side by side)",
                          "选择一段 TST 录像（多只小鼠并排悬挂）")
        panel.prompt = L("Analyse", "分析")
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func isMovie(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie)
    }
}

/// Shown only when the sheet was opened without a video (normally the open panel comes first).
struct TSTHomeView: View {
    @Environment(TSTAppModel.self) private var model
    var onChoose: () -> Void
    @State private var photoItem: PhotosPickerItem?
    @State private var dropTargeted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 42))
                        .foregroundStyle(.tint)
                    Text(L("Choose the TST recording", "选择悬尾实验录像"))
                        .font(.title2.bold())
                    Text(L("One video with several mice hanging side by side. Chambers and mice are found automatically; afterwards each chamber is saved as one session of one animal in this task.",
                           "一段视频中多只小鼠并排悬挂。程序会自动找到格子和小鼠；之后每个格子保存为此任务中一只小鼠的一次实验。"))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 520)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button(L("Choose video…", "选择视频…")) { onChoose() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                        PhotosPicker(selection: $photoItem, matching: .videos) {
                            Text(L("From Photos…", "从“照片”中选择…"))
                        }
                    }
                    .controlSize(.large)
                    Text(L("or drag a video file here", "也可以把视频文件拖到这里"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(36)
                .frame(maxWidth: 640)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                        .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
                )
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(dropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text(L("For reliable scoring", "录制建议")).font(.headline)
                    tip("camera.viewfinder", L("Fixed camera facing the front of the rig, every chamber in view.",
                                               "摄像机固定并正对装置，所有格子都在画面内。"))
                    tip("sun.max", L("Even, diffuse light; lock the camera's exposure so the brightness does not flicker.",
                                     "光线均匀柔和；锁定摄像机曝光，避免亮度闪烁。"))
                    tip("circle.lefthalf.filled", L("Dark mice on a light background. For light mice, change the mouse colour in Detection settings.",
                                                    "深色小鼠配浅色背景。如为浅色小鼠，请在“检测设置”中修改小鼠颜色。"))
                    tip("arrow.up.to.line", L("Use climb-stoppers (e.g. for C57BL/6); climbing is counted as “no mouse” frames.",
                                              "使用防爬装置（如 C57BL/6）；爬尾帧会计为“无小鼠”。"))
                }
                .frame(maxWidth: 640, alignment: .leading)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: TSTVideoPicker.isMovie) else { return false }
            model.open(url: url, name: url.lastPathComponent)
            return true
        } isTargeted: { dropTargeted = $0 }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    if let movie = try await item.loadTransferable(type: TSTPickedMovie.self) {
                        model.open(url: movie.url, name: movie.url.lastPathComponent)
                    }
                } catch {
                    model.errorMessage = L("Could not load the video: ", "无法载入视频：") + error.localizedDescription
                }
                photoItem = nil
            }
        }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(.tint)
        }
    }
}
