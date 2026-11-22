import SwiftUI
import UIKit

/// 原生手感工具：与网页震动桥同口径，原型里各手势/动作识别时震一次。
enum ProtoHaptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

/// 原生手感原型根视图：身份切换 + 星系图 + 服务列表 + 状态反馈条。
/// 数据是 ProtoData 的合成数据，与网页版互不相干；删服务只删本页内存数组，
/// 星系图与列表共用同一份数组（删了气泡也跟着少）。
struct ProtoRootView: View {
    var onExit: () -> Void

    @State private var identityID: String = "all"
    @State private var servicesByIdentity: [String: [ProtoService]] = [:]
    @State private var statusText: String = "原型页：捏合/拖动星系图，列表试左滑与长按"

    private var identity: ProtoIdentity { ProtoData.identity(identityID) }

    private var servicesBinding: Binding<[ProtoService]> {
        Binding(
            get: { servicesByIdentity[identityID] ?? [] },
            set: { servicesByIdentity[identityID] = $0 }
        )
    }

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.03)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                header
                identityChips
                ProtoGalaxyView(identityName: identity.name,
                                identityMark: identity.mark,
                                services: servicesBinding.wrappedValue,
                                onFeedback: { statusText = $0 })
                    .frame(height: 370)
                    .id(identityID)   // 切身份 = 星系图全新状态（缩放/平移归位）
                statusBar
                ProtoListView(services: servicesBinding,
                              identityValue: identity.value,
                              onFeedback: { statusText = $0 })
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if servicesByIdentity.isEmpty {
                var dict: [String: [ProtoService]] = [:]
                for idn in ProtoData.identities {
                    dict[idn.id] = ProtoData.services(for: idn.id)
                }
                servicesByIdentity = dict
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                onExit()
            } label: {
                Text("‹ 回网页版")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color(white: 0.16)))
            }
            Text("原生手感原型")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Text("合成数据")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    private var identityChips: some View {
        HStack(spacing: 8) {
            ForEach(ProtoData.identities) { idn in
                let selected = idn.id == identityID
                Button {
                    identityID = idn.id
                    ProtoHaptics.light()
                } label: {
                    Text(idn.name)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundColor(selected ? .white : .gray)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(selected ? Color.blue : Color(white: 0.13)))
                }
            }
            Spacer()
        }
    }

    private var statusBar: some View {
        HStack {
            Text(statusText)
                .font(.caption)
                .foregroundColor(Color(white: 0.85))
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.1)))
    }
}
