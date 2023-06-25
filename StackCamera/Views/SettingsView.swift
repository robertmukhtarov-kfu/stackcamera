//
//  FormatButton.swift
//  StackCamera
//
//  Created by Robert Mukhtarov on 02.04.2023
//

import SwiftUI

enum CompressedImageFormat: String {
    case jpeg
    case heif
}

enum BurstDestination: String, CaseIterable {
    case shareSheet
    case files
    case photos
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    
    @AppStorage("tileSize")
    private var tileSize = 0

    @AppStorage("compressedImageFormat")
    private var compressedImageFormat = CompressedImageFormat.heif.rawValue
    
    @AppStorage("burstDestination")
    private var burstDestination = BurstDestination.shareSheet.rawValue
    
    @AppStorage("isImageStabilizationEnabled")
    private var isImageStabilizationEnabled = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Tile Size", selection: $tileSize) {
                        Text("Auto").tag(0)
                        Text("8 × 8").tag(8)
                        Text("16 × 16").tag(16)
                        Text("32 × 32").tag(32)
                        Text("64 × 64").tag(64)
                    }
                } header: {
                    Text("Alignment Settings")
                }
                
                Section {
                    Toggle(isOn: $isImageStabilizationEnabled) {
                        Text("Optical Image Stabilization")
                    }
                } header: {
                    Text("Image Stabilization")
                }

                Picker("Compressed Image Format", selection: $compressedImageFormat) {
                    VStack(alignment: .leading, spacing: 4.0) {
                        Text("HEIF")
                        Text("High efficiency, uses less storage").font(.caption).foregroundColor(.gray)
                    }.tag("heif")
                    VStack(alignment: .leading, spacing: 4.0) {
                        Text("JPEG")
                        Text("High compatibility").font(.caption).foregroundColor(.gray)
                    }.tag("jpeg")
                }
                .pickerStyle(.inline)
                
                Picker("Burst Destination", selection: $burstDestination) {
                    Text("Photos").tag(BurstDestination.photos.rawValue)
                    Text("Files").tag(BurstDestination.files.rawValue)
                    Text("Share Sheet").tag(BurstDestination.shareSheet.rawValue)
                }
                .pickerStyle(.inline)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") {
                    dismiss()
                }.fontWeight(.semibold)
            }
        }
    }
}


struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
