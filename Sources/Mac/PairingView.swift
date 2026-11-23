import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

enum PairingQRCode {
    static func makeImage(for offer: PairingOffer) throws -> NSImage {
        var codeImage: NSImage?
        try offer.withQRPayload { payload in
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(payload.utf8)
            filter.correctionLevel = "M"
            guard let output = filter.outputImage,
                  let cgImage = CIContext().createCGImage(output, from: output.extent) else {
                throw PeerSessionError.internalFailure
            }
            codeImage = NSImage(cgImage: cgImage, size: NSSize(width: 280, height: 280))
        }
        guard let codeImage else { throw PeerSessionError.internalFailure }
        return codeImage
    }
}

struct PairingView: View {
    @ObservedObject var coordinator: MacCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Pair iPhone")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { coordinator.dismissPairingDetails() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close pairing")
            }

            if let image = coordinator.pairingCodeImage {
                VStack(spacing: 10) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 224, height: 224)
                        .accessibilityLabel("One-use QR code for pairing this Mac")
                    Text("Scan with the Near But Far iPhone app")
                        .font(.headline)
                    Text("Expires in \(coordinator.pairingSecondsRemaining) seconds. This code is only for setup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            if coordinator.pendingPhoneFingerprint != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A phone is requesting to pair.")
                        .font(.headline)
                    Text("Approve this request on the Mac to save the phone for future secure connections.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Cancel pairing", role: .cancel) { coordinator.cancelPairing() }
                        Spacer()
                        Button("Approve phone") {
                            do { try coordinator.approvePhone() }
                            catch { coordinator.cancelPairing() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            } else if coordinator.pairedPhoneFingerprint != nil, coordinator.pairingCodeImage == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Phone paired")
                        .font(.headline)
                    Button("Forget phone", role: .destructive) { coordinator.requestForgetPhone() }
                }
            } else {
                Text(coordinator.pairingAvailabilityMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !coordinator.pairingStatus.isEmpty,
               coordinator.pairingStatus != "A phone is requesting to pair." {
                Text(coordinator.pairingStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if coordinator.pairingCodeImage != nil {
                    Button("Cancel") { coordinator.cancelPairing() }
                } else if coordinator.pairedPhoneFingerprint != nil {
                    Button("Replace phone…") { coordinator.requestPairing() }
                } else if coordinator.pendingPhoneFingerprint == nil {
                    Button("Create a new code") { coordinator.requestPairing() }
                        .disabled(!coordinator.pairingCapability.isAvailable)
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 380)
        .confirmationDialog(
            "Replace the paired iPhone?",
            isPresented: $coordinator.isConfirmingReplacement,
            titleVisibility: .visible
        ) {
            Button("Forget current phone and continue", role: .destructive) {
                coordinator.confirmReplacementAndPair()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The existing phone will lose access before a new pairing code is created.")
        }
        .confirmationDialog(
            "Forget this phone?",
            isPresented: $coordinator.isConfirmingForget,
            titleVisibility: .visible
        ) {
            Button("Forget phone", role: .destructive) { coordinator.forgetPhone() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The phone will need to be paired again before it can reconnect.")
        }
    }
}
