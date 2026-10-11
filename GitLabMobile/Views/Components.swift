import SwiftUI

struct StatusBadge: View {
    let status: String

    var body: some View {
        Image(systemName: Self.symbol(status))
            .foregroundStyle(Self.color(status))
            .accessibilityLabel(status.replacingOccurrences(of: "_", with: " "))
    }

    static func symbol(_ s: String) -> String {
        switch s {
        case "success": "checkmark.circle.fill"
        case "failed": "xmark.circle.fill"
        case "running": "arrow.triangle.2.circlepath.circle.fill"
        case "pending", "created", "waiting_for_resource", "preparing", "scheduled": "clock.fill"
        case "manual": "play.circle.fill"
        case "canceled", "canceling": "stop.circle.fill"
        case "skipped": "arrow.right.circle.fill"
        default: "questionmark.circle.fill"
        }
    }

    static func color(_ s: String) -> Color {
        switch s {
        case "success": .green
        case "failed": .red
        case "running": .blue
        case "pending", "created", "waiting_for_resource", "preparing", "scheduled": .orange
        case "manual": .indigo
        default: .gray
        }
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
    }
}

/// Runs an async action, tracking busy state and surfacing errors.
@MainActor
func perform(busy: Binding<Bool>, error errorBinding: Binding<String?>,
             _ work: () async throws -> Void) async {
    busy.wrappedValue = true
    errorBinding.wrappedValue = nil
    defer { busy.wrappedValue = false }
    do { try await work() }
    catch is CancellationError {}
    catch { errorBinding.wrappedValue = error.localizedDescription }
}
