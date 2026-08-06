// StripboardView.swift
// A Movie Magic Scheduling-style stripboard: a vertically-scrolling list of
// full-width day sections, each a thin rule, a plain date header, another
// rule, then that day's scenes as dense color-coded strips — closer to a
// printed one-line/strip schedule than a UI card grid. An alternate to
// CompactMonthCalendarView's square calendar grid — same underlying
// shootDays/allScenes data, same drag-and-drop payload format, so the
// existing Boneyard sidebar (and its own drag-in/drag-out handling) works
// with this view for free.

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct StripboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var shootDays: [ShootDay]
    @Binding var allScenes: [Scene]
    let productionInfo: ProductionInfo
    @Binding var selectedSceneIDs: Set<UUID>
    @Binding var lastSelectedSceneID: UUID?
    let conflictDates: Set<Date>
    let conflictSceneIDs: Set<UUID>
    let duplicateSceneNumberIDs: Set<UUID>
    @Binding var scrollToDate: Date?
    let onSceneChanged: () -> Void
    let onCallSheetExport: (ShootDay) -> Void

    // Editing state — mirrors CompactMonthCalendarView's
    @State private var editingDayId:      UUID?
    @State private var editingDayIndex:   Int?
    @State private var editingSceneIndex: Int?
    @State private var showingEditSheet = false
    @State private var callSheetDay: ShootDay? = nil

    // Scene drag/drop state — own copy, independent of the calendar's
    @State private var dropTargetDayId:    UUID?
    @State private var dropTargetPosition: Int?
    @State private var interactingSceneId: UUID?

    // Day rearrange drag/drop state
    @State private var draggingDayId:   UUID?
    @State private var dayDropTargetId: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 10) {
                    ForEach(Array(shootDays.enumerated()), id: \.element.id) { dayIndex, day in
                        daySection(day: day, dayIndex: dayIndex)
                            .id(day.id)
                    }
                }
                .padding(10)
            }
            .onChange(of: scrollToDate) { _, newValue in
                guard let date = newValue else { return }
                if let target = shootDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                    withAnimation { proxy.scrollTo(target.id, anchor: .top) }
                }
                scrollToDate = nil
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tooltipContainer()
        .sheet(isPresented: $showingEditSheet) { editSheetContent() }
        .sheet(item: $callSheetDay) { day in callSheetEditorContent(for: day) }
        .onChange(of: showingEditSheet) { _, isShowing in
            if !isShowing { clearEditingState() }
        }
    }

    // MARK: - Day section

    @ViewBuilder
    private func daySection(day: ShootDay, dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            dayHeader(day: day)
            Divider().opacity(0.6)

            VStack(spacing: 1) {
                ForEach(Array(day.scenes.enumerated()), id: \.element.id) { sceneIndex, scene in
                    VStack(spacing: 0) {
                        if shouldShowDropIndicator(dayId: day.id, position: sceneIndex) {
                            DropIndicatorView()
                        }
                        SceneStripRow(
                            scene: scene,
                            interactingSceneId: $interactingSceneId,
                            isSelected: selectedSceneIDs.contains(scene.id),
                            selectionCount: selectedSceneIDs.count,
                            hasConflict: conflictSceneIDs.contains(scene.id),
                            hasDuplicateSceneNumber: duplicateSceneNumberIDs.contains(scene.id),
                            onEdit:      { editScene(dayIndex: dayIndex, sceneIndex: sceneIndex, dayId: day.id) },
                            onRemove:    { removeFromDay(scene, dayId: day.id) },
                            onDuplicate: { duplicateScene(scene) },
                            onDragStart: { interactingSceneId = scene.id },
                            onDragEnd:   { interactingSceneId = nil },
                            onSelect:    { selectScene(scene, dayId: day.id) }
                        )
                    }
                    .onDrop(of: [UTType.text.identifier], delegate: SceneDropDelegate(
                        dayId: day.id,
                        position: sceneIndex,
                        dropTargetDayId: $dropTargetDayId,
                        dropTargetPosition: $dropTargetPosition,
                        onDrop: { sceneId in handleSceneDrop(sceneId: sceneId, targetDayId: day.id, targetPosition: sceneIndex) }
                    ))
                }

                if shouldShowDropIndicator(dayId: day.id, position: day.scenes.count) {
                    DropIndicatorView()
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: day.scenes.isEmpty ? 36 : 0, alignment: .topLeading)
        }
        .background(
            ZStack {
                Color.gray.opacity(0.2)
                if isWeekend(day.date) {
                    Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    dayDropTargetId == day.id ? Color.green :
                    dropTargetDayId == day.id ? Color.red : Color.black,
                    lineWidth: (dayDropTargetId == day.id || dropTargetDayId == day.id) ? 2 : 1
                )
        )
        .cornerRadius(8)
        .onDrop(of: [UTType.text.identifier], delegate: CombinedDayDropDelegate(
            dayId: day.id,
            scenes: day.scenes,
            dropTargetDayId: $dropTargetDayId,
            dropTargetPosition: $dropTargetPosition,
            dayDropTargetId: $dayDropTargetId,
            draggingDayId: $draggingDayId,
            onSceneDrop: { sceneId in
                handleSceneDrop(sceneId: sceneId, targetDayId: day.id, targetPosition: day.scenes.count)
            },
            onDayDrop: { sourceDayId in
                handleDayRearrange(sourceDayId: sourceDayId, targetDayId: day.id)
            }
        ))
    }

    /// Plain, print-like date header — a grip handle for whole-day drag-to-
    /// rearrange, the date, call sheet/conflict indicators, and the day's
    /// scene count and page total. Click opens the call sheet, same as the
    /// calendar's date header.
    private func dayHeader(day: ShootDay) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(draggingDayId == day.id ? .blue : .secondary)
                .padding(4)
                .contentShape(Rectangle())
                .onDrag {
                    draggingDayId = day.id
                    return NSItemProvider(object: "day:\(day.id.uuidString)" as NSString)
                }
                .simultaneousGesture(TapGesture())   // absorbs tap so the button below doesn't fire
                .help("Drag to move this day's scenes and call sheet to another date")

            Button {
                callSheetDay = day
            } label: {
                HStack(spacing: 6) {
                    Text(formattedDate(day.date))
                        .font(.headline)
                    if day.hasCallSheetData {
                        Circle().fill(Color.blue).frame(width: 6, height: 6)
                    }
                    if conflictDates.contains(Calendar.current.startOfDay(for: day.date)) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9)).foregroundColor(.red)
                    }
                    Spacer()
                    if !day.scenes.isEmpty {
                        Text("\(day.scenes.count) scn · \(formattedEighths(day.totalDuration)) pgs")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Image(systemName: "doc.text")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .help("Click to open call sheet for this day")
    }

    // MARK: - Call sheet editor (mirrors CompactMonthCalendarView)

    @ViewBuilder
    private func callSheetEditorContent(for day: ShootDay) -> some View {
        if let idx = shootDays.firstIndex(where: { $0.id == day.id }) {
            CallSheetEditor(
                shootDay: $shootDays[idx],
                productionInfo: productionInfo,
                isPresented: Binding(
                    get: { callSheetDay != nil },
                    set: { if !$0 { callSheetDay = nil } }
                ),
                onSave: {
                    callSheetDay = nil
                    onSceneChanged()
                },
                onExportPDF: { exportDay in
                    onCallSheetExport(exportDay)
                }
            )
        }
    }

    // MARK: - Edit sheet (mirrors CompactMonthCalendarView)

    @ViewBuilder
    private func editSheetContent() -> some View {
        if let dayIndex   = editingDayIndex,
           let sceneIndex = editingSceneIndex,
           dayIndex   < shootDays.count,
           sceneIndex < shootDays[dayIndex].scenes.count {

            SceneEditSheet(
                scene: $shootDays[dayIndex].scenes[sceneIndex],
                isPresented: $showingEditSheet,
                onSave: {
                    onSceneChanged()
                },
                onDelete: {
                    if let id = editingDayId {
                        removeSceneDirect(shootDays[dayIndex].scenes[sceneIndex], dayId: id)
                        onSceneChanged()
                    }
                    clearEditingState()
                },
                canGoPrevious: sceneIndex > 0,
                canGoNext: sceneIndex < shootDays[dayIndex].scenes.count - 1,
                onPrevious: { editingSceneIndex = sceneIndex - 1 },
                onNext: { editingSceneIndex = sceneIndex + 1 },
                positionLabel: "Scene \(sceneIndex + 1) of \(shootDays[dayIndex].scenes.count)"
            )
        } else {
            VStack(spacing: 20) {
                Text("Error: Scene not found")
                    .font(.title2).foregroundColor(.red)
                Text("The scene may have been moved or deleted.")
                    .font(.body).multilineTextAlignment(.center)
                Button("Close") {
                    showingEditSheet = false
                    clearEditingState()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24).frame(width: 400)
        }
    }

    private func editScene(dayIndex: Int, sceneIndex: Int, dayId: UUID) {
        editingDayIndex   = dayIndex
        editingSceneIndex = sceneIndex
        editingDayId      = dayId
        showingEditSheet  = true
    }

    private func clearEditingState() {
        editingDayId      = nil
        editingDayIndex   = nil
        editingSceneIndex = nil
    }

    // MARK: - Scene drag & drop handling (mirrors CompactMonthCalendarView)

    private func shouldShowDropIndicator(dayId: UUID, position: Int) -> Bool {
        dropTargetDayId == dayId && dropTargetPosition == position
    }

    /// Accepts either a single scene ID or a comma-separated list (a Boneyard
    /// multi-selection) and inserts them, in order, starting at targetPosition.
    private func handleSceneDrop(sceneId: String, targetDayId: UUID, targetPosition: Int) {
        let ids = sceneId.components(separatedBy: ",").compactMap { UUID(uuidString: $0) }
        guard !ids.isEmpty else { return }

        var insertPosition = targetPosition
        for uuid in ids {
            // From the Boneyard
            if let idx = allScenes.firstIndex(where: { $0.id == uuid }) {
                let scene = allScenes.remove(at: idx)
                insertSceneIntoDay(scene: scene, dayId: targetDayId, position: insertPosition)
                insertPosition += 1
                continue
            }
            // From another (or the same) day
            for dayIdx in shootDays.indices {
                if let sceneIdx = shootDays[dayIdx].scenes.firstIndex(where: { $0.id == uuid }) {
                    let scene = shootDays[dayIdx].scenes.remove(at: sceneIdx)
                    var adjustedPos = insertPosition
                    if shootDays[dayIdx].id == targetDayId && sceneIdx < insertPosition { adjustedPos -= 1 }
                    insertSceneIntoDay(scene: scene, dayId: targetDayId, position: adjustedPos)
                    insertPosition += 1
                    break
                }
            }
        }
        onSceneChanged()
    }

    private func insertSceneIntoDay(scene: Scene, dayId: UUID, position: Int) {
        guard let dayIdx = shootDays.firstIndex(where: { $0.id == dayId }) else { return }
        let clamped = min(max(0, position), shootDays[dayIdx].scenes.count)
        shootDays[dayIdx].scenes.insert(scene, at: clamped)
    }

    /// Removes the clicked scene from its day back into the Boneyard — or, if it's
    /// part of a multi-scene selection, every selected scene currently scheduled
    /// anywhere on the board, mirroring the calendar's grouped removal.
    private func removeFromDay(_ scene: Scene, dayId: UUID) {
        if selectedSceneIDs.contains(scene.id), selectedSceneIDs.count > 1 {
            for dayIdx in shootDays.indices {
                let matching = shootDays[dayIdx].scenes.filter { selectedSceneIDs.contains($0.id) }
                for s in matching {
                    removeSceneDirect(s, dayId: shootDays[dayIdx].id)
                }
            }
        } else {
            removeSceneDirect(scene, dayId: dayId)
        }
        onSceneChanged()
    }

    private func removeSceneDirect(_ scene: Scene, dayId: UUID) {
        if let di = shootDays.firstIndex(where: { $0.id == dayId }) {
            shootDays[di].scenes.removeAll { $0.id == scene.id }
            allScenes.append(scene)
        }
    }

    private func duplicateScene(_ scene: Scene) {
        allScenes.append(Scene(
            title:         scene.title + " (Copy)",
            duration:      scene.duration,
            estimatedTime: scene.estimatedTime,
            dayNightType:  scene.dayNightType,
            cast:          scene.cast,
            summary:       scene.summary
        ))
        onSceneChanged()
    }

    // MARK: - Day rearrange (mirrors CompactMonthCalendarView.handleDayRearrange)

    /// Swaps scenes and call sheet between two days, preserving both dates —
    /// the calendar dates themselves never change, only the content moves.
    private func handleDayRearrange(sourceDayId: UUID, targetDayId: UUID) {
        guard sourceDayId != targetDayId,
              let sourceIdx = shootDays.firstIndex(where: { $0.id == sourceDayId }),
              let targetIdx = shootDays.firstIndex(where: { $0.id == targetDayId })
        else { return }

        let sourceScenes    = shootDays[sourceIdx].scenes
        let sourceCallSheet = shootDays[sourceIdx].callSheet
        let targetScenes    = shootDays[targetIdx].scenes
        let targetCallSheet = shootDays[targetIdx].callSheet

        shootDays[sourceIdx].scenes    = targetScenes
        shootDays[sourceIdx].callSheet = targetCallSheet
        shootDays[targetIdx].scenes    = sourceScenes
        shootDays[targetIdx].callSheet = sourceCallSheet

        draggingDayId   = nil
        dayDropTargetId = nil
        onSceneChanged()
    }

    // MARK: - Selection

    private func selectScene(_ scene: Scene, dayId: UUID) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selectedSceneIDs.contains(scene.id) { selectedSceneIDs.remove(scene.id) } else { selectedSceneIDs.insert(scene.id) }
            lastSelectedSceneID = scene.id
        } else if flags.contains(.shift),
                  let anchor = lastSelectedSceneID,
                  let dayIdx = shootDays.firstIndex(where: { $0.id == dayId }),
                  let anchorIdx = shootDays[dayIdx].scenes.firstIndex(where: { $0.id == anchor }),
                  let targetIdx = shootDays[dayIdx].scenes.firstIndex(where: { $0.id == scene.id }) {
            let range = anchorIdx < targetIdx ? anchorIdx...targetIdx : targetIdx...anchorIdx
            selectedSceneIDs.formUnion(range.map { shootDays[dayIdx].scenes[$0].id })
        } else {
            selectedSceneIDs = [scene.id]
            lastSelectedSceneID = scene.id
        }
    }
}

// MARK: - SceneStripRow

/// A single Movie Magic-style strip: scene number, title, cast, and page
/// count all on one dense, full-width line, color-coded by INT/EXT + Day/Night.
struct SceneStripRow: View {
    let scene: Scene
    @Binding var interactingSceneId: UUID?
    let isSelected:     Bool
    let selectionCount: Int
    let hasConflict:    Bool
    let hasDuplicateSceneNumber: Bool
    let onEdit:      () -> Void
    let onRemove:    () -> Void
    let onDuplicate: () -> Void
    let onDragStart: () -> Void
    let onDragEnd:   () -> Void
    let onSelect:    () -> Void

    private var isDragging: Bool { interactingSceneId == scene.id }
    private var isMultiSelected: Bool { isSelected && selectionCount > 1 }

    var body: some View {
        HStack(spacing: 8) {
            if !scene.sceneNumber.isEmpty {
                Text(scene.sceneNumber)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(scene.stripTextColor.opacity(0.6))
                    .lineLimit(1)
                    .frame(minWidth: 22, alignment: .leading)
            }

            Text(scene.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(scene.stripTextColor)
                .lineLimit(1)

            if hasConflict || hasDuplicateSceneNumber {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9)).foregroundColor(.red)
            }

            if !scene.cast.isEmpty {
                Text(scene.cast.joined(separator: ", "))
                    .font(.system(size: 10))
                    .foregroundColor(scene.stripTextColor.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(FractionParser.formatEighths(scene.duration))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(scene.stripTextColor.opacity(0.7))
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scene.stripColor.opacity(isDragging ? 0.7 : 1))
        .overlay(
            Rectangle()
                .stroke(isSelected ? Color.accentColor : scene.stripTextColor.opacity(0.2), lineWidth: isSelected ? 2 : 0.5)
        )
        .overlay(
            Rectangle()
                .strokeBorder(Color.red, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .opacity(hasDuplicateSceneNumber ? 1 : 0)
        )
        .scaleEffect(isDragging ? 1.01 : 1.0)
        .opacity(isDragging ? 0.85 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .fastTooltip(scene.tooltipText)
        .onDrag {
            interactingSceneId = scene.id
            onDragStart()
            return NSItemProvider(object: scene.id.uuidString as NSString)
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { interactingSceneId = nil; onEdit() })
        .simultaneousGesture(TapGesture(count: 1).onEnded { interactingSceneId = nil; onSelect() })
        .contextMenu {
            Button("Edit Scene") { interactingSceneId = nil; onEdit() }
            Button(isMultiSelected ? "Remove \(selectionCount) Scenes from Day" : "Remove from Day") {
                interactingSceneId = nil; onRemove()
            }
            Divider()
            Button("Duplicate Scene") { interactingSceneId = nil; onDuplicate() }
        }
        .onChange(of: isDragging) { _, dragging in
            if !dragging { onDragEnd() }
        }
    }
}
