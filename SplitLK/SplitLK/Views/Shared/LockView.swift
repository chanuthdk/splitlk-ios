import SwiftUI

struct LockView: View {
    let service: BiometricService

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color(hex: "4F46E5"))

            Text("SplitLK")
                .font(.largeTitle.bold())

            Text("Unlock to view your balances")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if case .failed(let message) = service.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 4)
            }

            Spacer()

            Button {
                Task { await service.authenticate() }
            } label: {
                Label("Unlock with \(service.biometryLabel)", systemImage: service.symbolName)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
