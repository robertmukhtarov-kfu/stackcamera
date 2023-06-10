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
                    Picker("Размер фрагмента", selection: $tileSize) {
                        Text("Авто").tag(0)
                        Text("8 × 8").tag(8)
                        Text("16 × 16").tag(16)
                        Text("32 × 32").tag(32)
                        Text("64 × 64").tag(64)
                    }
                } header: {
                    Text("Настройки выравнивания")
                }
                
                Section {
                    Toggle(isOn: $isImageStabilizationEnabled) {
                        Text("Оптическая стабилизация изображения")
                    }
                } header: {
                    Text("Стабилизация изображения")
                }

                Picker("Формат сжатых изображений", selection: $compressedImageFormat) {
                    VStack(alignment: .leading, spacing: 4.0) {
                        Text("HEIF")
                        Text("Высокая эффективность, использует меньше пространства").font(.caption).foregroundColor(.gray)
                    }.tag("heif")
                    VStack(alignment: .leading, spacing: 4.0) {
                        Text("JPEG")
                        Text("Высокая совместимость").font(.caption).foregroundColor(.gray)
                    }.tag("jpeg")
                }
                .pickerStyle(.inline)
                
                Picker("Место сохранения кадров серийной съемки", selection: $burstDestination) {
                    Text("Фото").tag(BurstDestination.photos.rawValue)
                    Text("Файлы").tag(BurstDestination.files.rawValue)
                    Text("Панель «Поделиться»").tag(BurstDestination.shareSheet.rawValue)
                }
                .pickerStyle(.inline)
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Готово") {
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
