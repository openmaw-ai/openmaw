import SwiftUI

struct UpgradeView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.yellow)
                Text("Upgrade to Pro")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Unlock the full power of OpenTolk Cloud")
                    .foregroundStyle(.secondary)
            }

            // Feature comparison
            VStack(spacing: 0) {
                comparisonHeader
                Divider()
                comparisonRow("Words / month", free: "5,000", pro: "Unlimited")
                Divider()
                comparisonRow("Max recording", free: "30s", pro: "120s")
                Divider()
                comparisonRow("Languages", free: "English", pro: "All Whisper-supported")
                Divider()
                comparisonRow("History entries", free: "20", pro: "50")
            }
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Own-key note
            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("Have your own API key? Use it for free forever with no limits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Pricing
            HStack(spacing: 12) {
                pricingCard(title: "Monthly", price: "$4.99", period: "/month", isPopular: false)
                pricingCard(title: "Annual", price: "$39.99", period: "/year", isPopular: true)
                pricingCard(title: "Lifetime", price: "$79.99", period: "once", isPopular: false)
            }

            // CTA
            Button {
                if AuthManager.shared.isSignedIn {
                    SubscriptionManager.shared.openCheckout()
                } else {
                    // Require sign-in before checkout
                    NSWorkspace.shared.open(URL(string: "opentolk://auth")!)
                }
            } label: {
                HStack {
                    Image(systemName: "creditcard")
                    Text("Continue to Checkout")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Dismiss
            Button("Maybe later") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.callout)
        }
        .padding(24)
        .frame(width: 420)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var comparisonHeader: some View {
        HStack {
            Text("Feature")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Free")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 80)
            Text("Pro")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .frame(width: 100)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func comparisonRow(_ feature: String, free: String, pro: String) -> some View {
        HStack {
            Text(feature)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(free)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80)
            Text(pro)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.blue)
                .frame(width: 100)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func pricingCard(title: String, price: String, period: String, isPopular: Bool) -> some View {
        VStack(spacing: 4) {
            if isPopular {
                Text("Best Value")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.blue)
                    .clipShape(Capsule())
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(price)
                .font(.title3)
                .fontWeight(.bold)
            Text(period)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(isPopular ? Color.blue.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isPopular ? Color.blue : Color.clear, lineWidth: 1.5)
        )
    }
}
