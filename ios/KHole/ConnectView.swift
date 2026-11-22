import SwiftUI

/// The first screen: pair with the computer by scanning the code Settings > Remote > Pair a phone shows. In the
/// phone app's look: the k-hole mark on black, one sentence, one button; lowercase like every k-hole screen.
struct ConnectView: View {
    @EnvironmentObject var model: AppModel
    @State private var scanning = false
    @State private var typing = false
    @State private var address = ""
    @State private var problem = ""

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image("Mark").resizable().scaledToFit().frame(width: 92, height: 92).accessibilityHidden(true)
            Text("k-hole").font(.system(size: 34, weight: .regular)).kerning(-0.8)
            Text("on your computer, open settings, remote, and pair a phone. then scan the code it shows.")
                .font(.system(size: 16)).foregroundStyle(Ink.muted).multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
            if !problem.isEmpty {
                Text(problem).font(.system(size: 14)).foregroundStyle(Ink.warn).multilineTextAlignment(.center).padding(.horizontal, 24)
            }
            Button { scanning = true } label: {
                Label("scan the code", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(GlassButton(primary: true))
            Button("type its address instead") { typing = true }
                .font(.system(size: 15)).foregroundStyle(Ink.muted).frame(minHeight: 44)
        }
        .padding(.horizontal, 20).padding(.bottom, 12)
        .foregroundStyle(Ink.text)
        .sheet(isPresented: $scanning) {
            QRScannerView { text in
                scanning = false
                if let url = URL(string: text), model.paired(with: url) { problem = "" }
                else { problem = "that isn't a k-hole pairing code. pair a phone on the computer and scan the code it shows." }
            }
            .ignoresSafeArea()
        }
        .alert("the computer's address", isPresented: $typing) {
            TextField("https://computer.tailnet.ts.net:8443", text: $address)
                .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
            Button("connect") {
                if let url = URL(string: address.trimmingCharacters(in: .whitespaces)), model.paired(with: url) { problem = "" }
                else { problem = "the address starts with https:// and names your computer." }
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("then pair with the pin it shows, as in the phone app.")
        }
    }
}

/// The phone app's colours (remote/app/switch.css, the dark look).
enum Ink {
    static let text = Color(red: 0.933, green: 0.945, blue: 0.925)
    static let muted = Color(red: 0.612, green: 0.659, blue: 0.667)
    static let accent = Color(red: 0.718, green: 0.843, blue: 0.761)
    static let warn = Color(red: 0.918, green: 0.718, blue: 0.396)
    static let fail = Color(red: 0.953, green: 0.608, blue: 0.576)
    static let glass = Color(hue: 0.555, saturation: 0.12, brightness: 0.14).opacity(0.86)
}

/// The phone app's glass button: a raised plane, the accent for the main one.
struct GlassButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(primary ? Color(red: 0.07, green: 0.12, blue: 0.09) : Ink.text)
            .background(primary ? AnyShapeStyle(Ink.accent) : AnyShapeStyle(Ink.glass), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(primary ? 0 : 0.12)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
