// NewSceneInputView.swift
// Sidebar form for manually creating and adding a new scene to the Boneyard

import SwiftUI

struct NewSceneInputView: View {
    @Binding var newSceneNumber: String
    @Binding var newSceneTitle: String
    @Binding var newDuration:   String
    @Binding var newEstimate:   String
    @Binding var allScenes:     [Scene]
    let onSceneAdded: () -> Void

    @State private var durationIsValid:      Bool         = true
    @State private var estimatedTimeIsValid: Bool         = true
    @State private var newDayNightType:      DayNightType = .day

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("#", text: $newSceneNumber)
                    .frame(width: 60)
                    .help("Scene number (optional)")
                TextField("Scene Title", text: $newSceneTitle)
            }

            // Duration field — optional for Custom strips
            VStack(alignment: .leading, spacing: 4) {
                TextField(FractionParser.placeholderText, text: $newDuration)
                    .border(durationIsValid ? Color.clear : Color.red, width: 1)
                    .onChange(of: newDuration) { validateDuration() }

                if !durationIsValid && !newDuration.isEmpty {
                    Text("Invalid format")
                        .font(.caption).foregroundColor(.red)
                } else if let eighths = FractionParser.parseToEighths(newDuration), !newDuration.isEmpty {
                    Text("= \(FractionParser.formatEighths(eighths)) pages")
                        .font(.caption).foregroundColor(.secondary)
                } else if newDuration.isEmpty {
                    Text("Leave blank for no page count")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            // Time field — optional for Custom strips
            VStack(alignment: .leading, spacing: 4) {
                TextField(TimeParser.placeholderText, text: $newEstimate)
                    .border(estimatedTimeIsValid ? Color.clear : Color.red, width: 1)
                    .onChange(of: newEstimate) { validateEstimatedTime() }

                if !estimatedTimeIsValid && !newEstimate.isEmpty {
                    Text("Invalid time format")
                        .font(.caption).foregroundColor(.red)
                } else if let hint = TimeParser.getInputHint(newEstimate), !newEstimate.isEmpty {
                    Text(hint).font(.caption).foregroundColor(.secondary)
                } else if newEstimate.isEmpty {
                    Text("Leave blank for no time estimate")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            // Day / Night / Custom toggle
            HStack(spacing: 15) {
                Text("Time:").font(.caption).foregroundColor(.secondary)

                ForEach(DayNightType.allCases, id: \.self) { type in
                    Button {
                        newDayNightType = type
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: newDayNightType == type ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(newDayNightType == type ? type.color : .secondary)
                                .font(.caption)
                            Text(type == .custom ? "Custom" : type.displayName)
                                .font(.caption)
                                .foregroundColor(newDayNightType == type ? type.color : .primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Add Scene") { addScene() }
                .disabled(!canAddScene())
                .padding(.top, 5)
        }
    }

    // MARK: - Helpers

    private func validateDuration() {
        durationIsValid = FractionParser.parseToEighths(newDuration) != nil || newDuration.isEmpty
    }

    private func validateEstimatedTime() {
        estimatedTimeIsValid = TimeParser.parseToMinutes(newEstimate) != nil || newEstimate.isEmpty
    }

    /// A title is the only thing a scene actually needs — duration and time
    /// are always optional and default to zero when left blank, since a
    /// notice strip (no scene number, e.g. "DOWN FOR THANKSGIVING") often has
    /// neither. Non-empty text in either field still has to actually parse.
    private func canAddScene() -> Bool {
        let titleOK = !newSceneTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return titleOK && durationIsValid && estimatedTimeIsValid
    }

    private func addScene() {
        guard !newSceneTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let duration = FractionParser.parseToEighths(newDuration) ?? 0
        let estimate = TimeParser.parseToMinutes(newEstimate) ?? 0

        allScenes.append(Scene(
            title:         newSceneTitle,
            sceneNumber:   newSceneNumber.trimmingCharacters(in: .whitespaces),
            duration:      duration,
            estimatedTime: estimate,
            dayNightType:  newDayNightType
        ))

        newSceneNumber  = ""
        newSceneTitle   = ""
        newDuration     = ""
        newEstimate     = ""
        newDayNightType = .day
        onSceneAdded()
    }
}
