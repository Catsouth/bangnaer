import SwiftUI
import UIKit

/// 原生服务列表原型：左滑与长按全部用系统组件，不手写手势。
/// - .swipeActions：红「删除」+ 蓝「更多」（更多打开 confirmationDialog）
/// - .contextMenu：长按菜单（前往登录/复制账号/复制身份/编辑/删除）
/// 动作只给反馈：复制真写剪贴板，删除真从数组移除，其余报状态文字。
struct ProtoListView: View {
    @Binding var services: [ProtoService]
    let identityValue: String
    var onFeedback: (String) -> Void

    @State private var actionTarget: ProtoService? = nil
    @State private var showActions = false

    var body: some View {
        List {
            ForEach(services) { svc in
                row(svc)
            }
        }
        .listStyle(.plain)
        .confirmationDialog(actionTarget?.name ?? "服务操作",
                            isPresented: $showActions,
                            titleVisibility: .visible) {
            Button("前往登录") {
                if let svc = actionTarget { feedback("前往登录 \(svc.name)（原型：未真打开）") }
            }
            Button("复制账号") {
                if let svc = actionTarget { copyAccount(svc) }
            }
            Button("复制身份") { copyIdentity() }
            Button("编辑") {
                if let svc = actionTarget { feedback("编辑 \(svc.name)（原型：未做编辑页）") }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(actionTarget?.domain ?? "")
        }
    }

    @ViewBuilder
    private func row(_ svc: ProtoService) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(white: 0.16))
                Text(svc.initial)
                    .font(.headline)
                    .foregroundColor(svc.tint)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(svc.name)
                    .foregroundColor(.white)
                Text(svc.domain)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .listRowBackground(Color(white: 0.07))
        .onTapGesture {
            ProtoHaptics.light()
            onFeedback("已选中 \(svc.name)（\(svc.domain)）")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                delete(svc)
            } label: {
                Label("删除", systemImage: "trash")
            }
            .tint(.red)
            Button {
                actionTarget = svc
                showActions = true
            } label: {
                Label("更多", systemImage: "ellipsis")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                feedback("前往登录 \(svc.name)（原型：未真打开）")
            } label: {
                Label("前往登录", systemImage: "arrow.up.forward.square")
            }
            Button {
                copyAccount(svc)
            } label: {
                Label("复制账号", systemImage: "doc.on.doc")
            }
            Button {
                copyIdentity()
            } label: {
                Label("复制身份", systemImage: "person.crop.circle")
            }
            Button {
                feedback("编辑 \(svc.name)（原型：未做编辑页）")
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive) {
                delete(svc)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: - 动作（原型口径：给反馈，不接真实业务）

    private func feedback(_ text: String) {
        ProtoHaptics.light()
        onFeedback(text)
    }

    private func copyAccount(_ svc: ProtoService) {
        UIPasteboard.general.string = svc.account
        feedback("已复制 \(svc.name) 的账号")
    }

    private func copyIdentity() {
        UIPasteboard.general.string = identityValue
        feedback("已复制身份：\(identityValue)")
    }

    private func delete(_ svc: ProtoService) {
        if let idx = services.firstIndex(where: { $0.id == svc.id }) {
            services.remove(at: idx)
        }
        ProtoHaptics.medium()
        onFeedback("已删除 \(svc.name)（原型：仅本地移除）")
    }
}
