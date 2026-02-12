//
//  SettingsTabView.swift
//  OpenCodeClient
//

import SwiftUI

struct SettingsTabView: View {
    @Bindable var state: AppState

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Connection") {
                    TextField("Address", text: $state.serverURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)

                    TextField("Username", text: $state.username)
                        .textContentType(.username)
                        .autocapitalization(.none)

                    SecureField("Password", text: $state.password)
                        .textContentType(.password)

                    HStack {
                        Text("Status")
                        Spacer()
                        if state.isConnected {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Disconnected", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    if let error = state.connectionError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Test Connection") {
                        Task { await state.testConnection() }
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $state.themePreference) {
                        Text("Auto").tag("auto")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }
                Section("About") {
                    if let version = state.serverVersion {
                        LabeledContent("Server Version", value: version)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
