import SwiftUI

/// 连接主页：大标题 + 插画 + 两个入口按钮 + 脚注。
struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text("连接电视")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("扫描电视上的二维码")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)

            Spacer()
            PairingIllustration()
                .padding(.horizontal, 40)
            Spacer()

            VStack(spacing: 12) {
                Button {
                    model.screen = .scan
                } label: {
                    Label("扫码连接", systemImage: "qrcode.viewfinder")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.blue, in: Capsule())
                }
                Button {
                    model.screen = .manual
                } label: {
                    Text("输入电视地址")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(hex: "#EFEDE8")!, in: Capsule())
                }
                Text("无需注册")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 24)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

/// 电视 + 手机简化插画（对齐设计稿 01）。
struct PairingIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .bottomLeading) {
                // 电视
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white)
                        .frame(width: w, height: h * 0.62)
                        .overlay(
                            TVScreenDoodle()
                                .padding(6)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.ink.opacity(0.8), lineWidth: 2)
                        )
                    HStack(spacing: w * 0.5) {
                        Leg()
                        Leg()
                    }
                    .frame(height: h * 0.14)
                }
                // 手机
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white)
                    .frame(width: w * 0.24, height: h * 0.44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.ink, lineWidth: 2)
                    )
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "wifi")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.blue)
                            .padding(4)
                    }
                    .offset(x: -w * 0.06, y: -h * 0.1)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
        .frame(height: 210)
    }

    struct Leg: View {
        var body: some View {
            Rectangle()
                .fill(Theme.ink.opacity(0.8))
                .frame(width: 4, height: 22)
        }
    }

    struct TVScreenDoodle: View {
        var body: some View {
            ZStack {
                // 山
                Mountain(offset: 0.15)
                Mountain(offset: -0.15)
                // 太阳
                Circle()
                    .fill(Theme.orange)
                    .frame(width: 26, height: 26)
                    .offset(x: -40, y: -34)
                // 树
                VStack(spacing: 2) {
                    Circle().fill(Theme.green).frame(width: 20, height: 20)
                    Rectangle().fill(Color(hex: "#8B5A2B")!).frame(width: 3, height: 10)
                }
                .offset(x: 62, y: -14)
            }
        }

        struct Mountain: View {
            let offset: CGFloat
            var body: some View {
                MountainShape()
                    .fill(Theme.blue.opacity(0.85))
                    .offset(y: offset)
            }
        }

        struct MountainShape: Shape {
            func path(in rect: CGRect) -> Path {
                var path = Path()
                let baseY = rect.maxY
                let top = rect.height * 0.45
                path.move(to: CGPoint(x: rect.width * 0.05, y: baseY))
                path.addLine(to: CGPoint(x: rect.width * 0.3, y: top))
                path.addLine(to: CGPoint(x: rect.width * 0.52, y: baseY))
                path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.55))
                path.addLine(to: CGPoint(x: rect.width * 0.95, y: baseY))
                path.closeSubpath()
                return path
            }
        }
    }
}
