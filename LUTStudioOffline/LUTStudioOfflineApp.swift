import CryptoKit
import SwiftUI

@main
struct LUTStudioOfflineApp: App {
    @State private var passwordEntry = ""
    @State private var isUnlocked = false
    @State private var showWelcome = false
    @State private var hasError = false

    // SHA-256 digest of the user-selected app access code.
    // This is an app-entry deterrent, not a way to protect the source code from reverse engineering.
    private let accessCodeDigest = "89d8b7c49eeda7cf15b25f43b278619a53f876a842b6cc2ed720f3d3294fdc7b"

    var body: some Scene {
        WindowGroup {
            ZStack {
                ProjectsHomeView()
                    .preferredColorScheme(.dark)
                    .blur(radius: isUnlocked ? 0 : 12)
                    .disabled(!isUnlocked)

                if !isUnlocked {
                    lockPopup
                        .transition(.opacity)
                        .zIndex(2)
                } else if showWelcome {
                    welcomePopup
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(3)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: isUnlocked)
        }
    }

    private var lockPopup: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Color(red: 0.66, green: 1, blue: 0.16))
                Text("LUT STUDIO")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Devam etmek için erişim kodunu girin")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                SecureField("Erişim kodu", text: $passwordEntry)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .padding(15)
                    .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .onSubmit(checkPassword)
                if hasError {
                    Text("Kod hatalı. Tekrar deneyin.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red.opacity(0.9))
                }
                Button(action: checkPassword) {
                    Text("Giriş yap")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.66, green: 1, blue: 0.16), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }
            .padding(26)
            .frame(maxWidth: 340)
            .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .padding(24)
        }
    }

    private var welcomePopup: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(Color(red: 0.66, green: 1, blue: 0.16))
                Text("Ufuk Bey hizmetinizdeyim")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("Devam et") {
                    showWelcome = false
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 34)
                .padding(.vertical, 12)
                .background(Color(red: 0.66, green: 1, blue: 0.16), in: Capsule())
            }
            .padding(28)
            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 22))
            .padding(28)
        }
    }

    private func checkPassword() {
        let enteredDigest = SHA256.hash(data: Data(passwordEntry.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard enteredDigest == accessCodeDigest else {
            hasError = true
            passwordEntry = ""
            return
        }
        hasError = false
        passwordEntry = ""
        isUnlocked = true
        showWelcome = true
    }
}
