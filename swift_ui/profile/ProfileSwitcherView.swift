import SwiftUI

struct ProfileSwitcherView: View {
    @ObservedObject var coordinator: ProfileCoordinator

    @State private var editingProfile: UserProfile?
    @State private var isCreatingProfile = false
    @State private var showFamilyDashboard = false
    @State private var pendingDeletion: UserProfile?
    @State private var confirmingDataErasure: UserProfile?

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            VStack(spacing: 6) {
                Text("Who's using Composure?")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("Each person gets their own history, baselines, and goals.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), spacing: Spacing.lg)],
                spacing: Spacing.lg
            ) {
                ForEach(coordinator.profiles) { profile in
                    ProfileChip(profile: profile) {
                        coordinator.select(profile)
                    }
                    .contextMenu {
                        Button("Rename & Edit") { editingProfile = profile }
                        if coordinator.canDelete(profile) {
                            Button("Remove from list", role: .destructive) {
                                pendingDeletion = profile
                            }
                        }
                    }
                }

                Button(action: { isCreatingProfile = true }) {
                    VStack(spacing: 8) {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                            .frame(width: 64, height: 64)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                            )
                        Text("Add profile")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 420)

            Button(action: { showFamilyDashboard = true }) {
                Label("Family overview", systemImage: "person.3.sequence")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(BrandColor.teal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandColor.slate)
        .sheet(isPresented: $isCreatingProfile) {
            ProfileEditorSheet(mode: .create, coordinator: coordinator)
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditorSheet(mode: .edit(profile), coordinator: coordinator)
        }
        .sheet(isPresented: $showFamilyDashboard) {
            FamilyDashboardView(profiles: coordinator.profiles)
                .frame(minWidth: 480, minHeight: 560)
        }
        // Two-step deletion, deliberately. The first confirmation only
        // removes the profile from this list; a second, separate prompt
        // is required before any data actually disappears — see the note
        // on `ProfileCoordinator.permanentlyDeleteData(for:)`.
        .alert(
            "Remove \(pendingDeletion?.name ?? "this profile")?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
        ) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Remove from list") {
                if let profile = pendingDeletion {
                    coordinator.remove(profile)
                }
                pendingDeletion = nil
            }
            if let profile = pendingDeletion {
                Button("Remove and delete their data", role: .destructive) {
                    confirmingDataErasure = profile
                    pendingDeletion = nil
                }
            }
        } message: {
            Text("Their sessions, goals, and logs stay on disk unless you choose to delete them too.")
        }
        .alert(
            "Permanently delete \(confirmingDataErasure?.name ?? "")'s data?",
            isPresented: Binding(get: { confirmingDataErasure != nil }, set: { if !$0 { confirmingDataErasure = nil } })
        ) {
            Button("Cancel", role: .cancel) { confirmingDataErasure = nil }
            Button("Delete everything", role: .destructive) {
                if let profile = confirmingDataErasure {
                    try? coordinator.permanentlyDeleteData(for: profile)
                    coordinator.remove(profile)
                }
                confirmingDataErasure = nil
            }
        } message: {
            Text("Every session, streak, and log they've ever recorded will be gone. This can't be undone.")
        }
    }
}

// MARK: - Chip

private struct ProfileChip: View {
    let profile: UserProfile
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(profile.colorTag.color.opacity(0.25))
                        .frame(width: 64, height: 64)
                    Circle()
                        .stroke(profile.colorTag.color.opacity(0.6), lineWidth: 1.5)
                        .frame(width: 64, height: 64)
                    Text(profile.initial)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(profile.colorTag.color)
                }

                VStack(spacing: 1) {
                    Text(profile.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(profile.relationship.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Editor Sheet

private struct ProfileEditorSheet: View {
    enum Mode {
        case create
        case edit(UserProfile)
    }

    let mode: Mode
    @ObservedObject var coordinator: ProfileCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var relationship: ProfileRelationship = .adult
    @State private var colorTag: ProfileColorTag = .teal

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(isEditing ? "Edit profile" : "New profile")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Type").font(.caption).foregroundStyle(.white.opacity(0.7))
                Picker("", selection: $relationship) {
                    ForEach(ProfileRelationship.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Colour").font(.caption).foregroundStyle(.white.opacity(0.7))
                HStack(spacing: Spacing.md) {
                    ForEach(ProfileColorTag.allCases, id: \.self) { tag in
                        Circle()
                            .fill(tag.color)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle().stroke(.white, lineWidth: colorTag == tag ? 2 : 0)
                            )
                            .onTapGesture { colorTag = tag }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(BrandColor.primaryBlue)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(minWidth: 360)
        .background(BrandColor.slate)
        .onAppear(perform: prefill)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func prefill() {
        guard case .edit(let profile) = mode else { return }
        name = profile.name
        relationship = profile.relationship
        colorTag = profile.colorTag
    }

    private func save() {
        switch mode {
        case .create:
            coordinator.createProfile(name: name, relationship: relationship, colorTag: colorTag)
        case .edit(let profile):
            coordinator.rename(profile, to: name)
            coordinator.updateAppearance(profile, relationship: relationship, colorTag: colorTag)
        }
        dismiss()
    }
}

#if DEBUG
#Preview {
    ProfileSwitcherView(coordinator: ProfileCoordinator(store: InMemoryProfileStore(
        state: ProfilesState(
            profiles: [.default, UserProfile(name: "Sam", relationship: .teen, colorTag: .coral)],
            activeProfileID: nil
        )
    )))
    .frame(width: 600, height: 500)
}
#endif
