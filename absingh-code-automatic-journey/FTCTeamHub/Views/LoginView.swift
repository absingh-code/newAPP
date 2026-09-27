//
//  LoginView.swift
//  FTCTeamHub
//
//  Native, clean sign-in / account-creation flow. Segmented control toggles
//  between "Sign In" and "Create Account" in one screen rather than
//  separate pushed views, matching Apple's own first-party pattern (see
//  Apple Music / Fitness account screens).
//

import SwiftUI
import UIKit

struct LoginView: View {
    @Environment(AuthenticationManager.self) private var authManager

    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign In", signUp = "Create Account"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var role: TeamRole = .builder
    @State private var avatarColor: AvatarColor = .blue
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: mode) { authManager.errorMessage = nil }

                    formFields
                        .padding(.horizontal)

                    if mode == .signUp {
                        profileSetup
                            .padding(.horizontal)
                    }

                    if let error = authManager.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    submitButton
                        .padding(.horizontal)
                        .padding(.top, 4)

                    Spacer(minLength: 24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "shield.checkerboard")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .padding(.top, 40)
            Text("FTC Team Hub")
                .font(.title2.bold())
            Text(mode == .signIn ? "Sign in to your team workspace" : "Set up your team member profile")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var formFields: some View {
        VStack(spacing: 12) {
            if mode == .signUp {
                TextField("Full name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
            }
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(mode == .signUp ? .newPassword : .password)
        }
    }

    private var profileSetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Team Role").font(.caption).foregroundStyle(.secondary)
                Picker("Role", selection: $role) {
                    ForEach(TeamRole.allCases) { r in
                        Label(r.rawValue, systemImage: r.systemImage).tag(r)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Avatar Color").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(AvatarColor.allCases) { swatch in
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 32, height: 32)
                            .overlay {
                                if avatarColor == swatch {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                avatarColor = swatch
                            }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            if isSubmitting {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text(mode == .signIn ? "Sign In" : "Create Account")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isValid || isSubmitting)
    }

    private var isValid: Bool {
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty, password.count >= 4 else { return false }
        if mode == .signUp { return !name.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private func submit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSubmitting = true
        switch mode {
        case .signIn:
            authManager.signIn(email: email, password: password)
        case .signUp:
            authManager.signUp(name: name, email: email, password: password, role: role, avatarColor: avatarColor)
        }
        isSubmitting = false
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    authManager.signOut() // show the logged-out state in the preview
    return LoginView()
        .modelContainer(container)
        .environment(authManager)
}
