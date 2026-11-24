import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 文件选择器（第十四轮：弃用 SwiftUI .fileImporter）
//
// 第十三轮已把两处 .fileImporter 的 allowedContentTypes 补到含 .item
// 根类型、Info.plist 文档类型收窄为只声明 public.json，并验进构建
// 1042 的包；用户真机上从本 App 刚导出的 .json 备份在「导入备份」
// 选择器里仍然置灰点不动，同一通道在她机器上自第一批起从未通过。
// 结论：.fileImporter 的类型过滤在这条路径上不可靠，不再跟它纠缠，
// 改走 UIKit 原生 UIDocumentPickerViewController 手写包装：
// - forOpeningContentTypes 只给 [UTType.item]（一切文件类型的根），
//   不给任何具体类型，系统没有可据以置灰的类型条件；
// - asCopy: true，选中即由系统把文件拷入本 App 沙盒，回调拿到的
//   URL 是沙盒内副本路径，可直接 Data(contentsOf:) 读取，不需要、
//   也不要再套 startAccessingSecurityScopedResource（对普通副本
//   URL 套用只会徒增卡死风险）；
// - 取消静默返回；读取/解析失败由调用方走既有页内反馈（导入备份
//   的 store.show、智能导入的 setFeedback），这里不吞错也不弹窗。

struct DocPicker: UIViewControllerRepresentable {
  var onPick: (URL) -> Void
  var onCancel: () -> Void = {}

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item], asCopy: true)
    picker.allowsMultipleSelection = false
    picker.shouldShowFileExtensions = true
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    var parent: DocPicker
    init(_ parent: DocPicker) { self.parent = parent }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
      // 空数组是理论上的边角：当作取消收起，不许把 sheet 干挂着无终局。
      if let url = urls.first { parent.onPick(url) } else { parent.onCancel() }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
      parent.onCancel()
    }
  }
}

extension View {
  /// 以 sheet 形式拉起 DocPicker。选中后先收起 sheet、延迟 300ms
  /// 再执行 onPick——与第十三轮 popover 添加路由同一手法，避免回调
  /// 里的后续动作（导入成功后 dismiss 设置页、页内提示）压在还在
  /// 退场的 sheet 上；取消则只收起，不回调。
  func docPickerSheet(isPresented: Binding<Bool>, onPick: @escaping (URL) -> Void) -> some View {
    sheet(isPresented: isPresented) {
      DocPicker(
        onPick: { url in
          isPresented.wrappedValue = false
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onPick(url) }
        },
        onCancel: { isPresented.wrappedValue = false }
      )
      .ignoresSafeArea()
    }
  }
}
