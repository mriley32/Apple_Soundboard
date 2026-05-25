import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Models

enum SidebarTab: String, CaseIterable, Identifiable {
    case presets = "Presets"
    case animals = "Animals"
    case custom = "Custom Board"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .presets: return "shield.fill"
        case .animals: return "pawprint.fill"
        case .custom: return "slider.horizontal.3"
        }
    }
}

struct SoundDefinition: Identifiable {
    let id: String
    let name: String
    let relativePath: String
    let sfSymbol: String
    var isLooping: Bool = false
}

struct CustomSlotConfig: Codable, Identifiable {
    var id: Int
    var name: String?
    var filePath: String?
    var emoji: String?
    var isLooping: Bool = false
    
    var displayName: String {
        name ?? "Click to add sound"
    }
    
    var activeEmoji: String {
        emoji ?? "🎵"
    }
}

// MARK: - Audio Engine Helper & Delegate

struct ActivePlayerInstance {
    let player: AVAudioPlayer
    let delegate: PlayerDelegate
}

class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let soundId: String
    weak var engine: SoundboardAudioEngine?
    let player: AVAudioPlayer
    
    init(soundId: String, engine: SoundboardAudioEngine, player: AVAudioPlayer) {
        self.soundId = soundId
        self.engine = engine
        self.player = player
        super.init()
        player.delegate = self
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        engine?.playerDidFinish(player, soundId: soundId)
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        engine?.playerDidFinish(player, soundId: soundId)
    }
}

// MARK: - Audio Engine

class SoundboardAudioEngine: ObservableObject {
    @Published var activeInstances: [String: [ActivePlayerInstance]] = [:]
    @Published var loopStates: [String: Bool] = [:]
    @Published var masterVolume: Float = 0.8 {
        didSet {
            updateVolumes()
        }
    }
    @Published var isAnySoundPlaying: Bool = false
    
    private let fileManager = FileManager.default
    
    // Check if a sound is currently playing
    func playingCount(for soundId: String) -> Int {
        return activeInstances[soundId]?.count ?? 0
    }
    
    // Plays a sound by its ID and path
    func playSound(id: String, path: String) {
        guard let url = resolveSoundPath(path) else {
            alertError(message: "Could not find sound file: \(path)")
            return
        }
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            
            let isLoop = loopStates[id] ?? false
            player.numberOfLoops = isLoop ? -1 : 0
            player.volume = masterVolume
            
            let delegate = PlayerDelegate(soundId: id, engine: self, player: player)
            let instance = ActivePlayerInstance(player: player, delegate: delegate)
            
            DispatchQueue.main.async {
                if self.activeInstances[id] == nil {
                    self.activeInstances[id] = []
                }
                self.activeInstances[id]?.append(instance)
                self.isAnySoundPlaying = true
                player.play()
            }
        } catch {
            alertError(message: "Failed to play sound: \(error.localizedDescription)")
        }
    }
    
    // Stop all instances of a specific sound
    func stopSound(id: String) {
        guard let instances = activeInstances[id] else { return }
        
        for instance in instances {
            instance.player.stop()
        }
        
        DispatchQueue.main.async {
            self.activeInstances.removeValue(forKey: id)
            self.updateIsAnySoundPlaying()
        }
    }
    
    // Stop every active sound
    func stopAllSounds() {
        for (_, instances) in activeInstances {
            for instance in instances {
                instance.player.stop()
            }
        }
        
        DispatchQueue.main.async {
            self.activeInstances.removeAll()
            self.isAnySoundPlaying = false
        }
    }
    
    // Update looping state for a sound ID
    func setLooping(id: String, looping: Bool) {
        loopStates[id] = looping
        
        // Dynamically update currently running players
        if let instances = activeInstances[id] {
            for instance in instances {
                instance.player.numberOfLoops = looping ? -1 : 0
            }
        }
    }
    
    func isLooping(id: String) -> Bool {
        return loopStates[id] ?? false
    }
    
    // Dynamic volume adjustment for active players
    private func updateVolumes() {
        for (_, instances) in activeInstances {
            for instance in instances {
                instance.player.volume = masterVolume
            }
        }
    }
    
    // Clean up finished playbacks
    func playerDidFinish(_ player: AVAudioPlayer, soundId: String) {
        DispatchQueue.main.async {
            guard var instances = self.activeInstances[soundId] else { return }
            if let index = instances.firstIndex(where: { $0.player === player }) {
                instances.remove(at: index)
                if instances.isEmpty {
                    self.activeInstances.removeValue(forKey: soundId)
                } else {
                    self.activeInstances[soundId] = instances
                }
            }
            self.updateIsAnySoundPlaying()
        }
    }
    
    private func updateIsAnySoundPlaying() {
        self.isAnySoundPlaying = !activeInstances.values.flatMap({ $0 }).isEmpty
    }
    
    // Robust local file path resolution for both relative preset sounds and custom user paths
    private func resolveSoundPath(_ path: String) -> URL? {
        // Direct absolute path check (for user custom files)
        if path.hasPrefix("/") {
            let url = URL(fileURLWithPath: path)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        
        // 1. Check parent directory of the bundle (ideal for adjacent 'sounds' folder in build environment)
        let parentDirUrl = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(path)
        if fileManager.fileExists(atPath: parentDirUrl.path) {
            return parentDirUrl
        }
        
        // 2. Check current working directory
        let cwdUrl = URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(path)
        if fileManager.fileExists(atPath: cwdUrl.path) {
            return cwdUrl
        }
        
        // 3. Check relative to executable directory
        if let execUrl = Bundle.main.executableURL {
            let execDirUrl = execUrl.deletingLastPathComponent().appendingPathComponent(path)
            if fileManager.fileExists(atPath: execDirUrl.path) {
                return execDirUrl
            }
        }
        
        // 4. Check inside bundle resources (fallback)
        if let resourceUrl = Bundle.main.url(forResource: path, withExtension: nil) {
            return resourceUrl
        }
        
        // Fallback: direct relative URL
        return URL(fileURLWithPath: path)
    }
    
    private func alertError(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Soundboard Audio Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// MARK: - Custom Views: Siri-style Visualizer

struct EqualizerView: View {
    let isAnimating: Bool
    @State private var waveHeights: [CGFloat] = Array(repeating: 6, count: 12)
    let timer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<waveHeights.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.purple, .indigo, .pink],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 4, height: waveHeights[index])
                    .animation(.easeInOut(duration: 0.11), value: waveHeights[index])
            }
        }
        .frame(height: 35)
        .padding(.vertical, 8)
        .onReceive(timer) { _ in
            if isAnimating {
                // Generate natural-looking bouncing EQ peaks
                for i in 0..<waveHeights.count {
                    waveHeights[i] = CGFloat.random(in: 4...32)
                }
            } else {
                // Flat/idle state
                for i in 0..<waveHeights.count {
                    waveHeights[i] = 6
                }
            }
        }
    }
}

// MARK: - Individual Sound Button View

struct SoundButton: View {
    let id: String
    let name: String
    let emoji: String?
    let sfSymbol: String?
    let path: String?
    let themeColor: Color
    
    @ObservedObject var engine: SoundboardAudioEngine
    var onClickAdd: (() -> Void)? = nil
    
    var isAssigned: Bool {
        return path != nil
    }
    
    var isPlaying: Bool {
        return engine.playingCount(for: id) > 0
    }
    
    var isLooping: Bool {
        return engine.isLooping(id: id)
    }
    
    var body: some View {
        Button(action: {
            if isAssigned {
                if let path = path {
                    engine.playSound(id: id, path: path)
                }
            } else {
                onClickAdd?()
            }
        }) {
            ZStack {
                // Background Card Styling
                RoundedRectangle(cornerRadius: 12)
                    .fill(isAssigned ? themeColor.opacity(0.12) : Color.gray.opacity(0.05))
                    .background(.thinMaterial)
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                
                // Active glowing glow if looped
                if isLooping {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.9), lineWidth: 2.5)
                        .shadow(color: .green.opacity(0.4), radius: 3)
                } else if isAssigned {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(themeColor.opacity(0.3), lineWidth: 1)
                } else {
                    // Dotted border for unassigned slots
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .foregroundColor(.gray.opacity(0.4))
                }
                
                // Inside Contents
                VStack(spacing: 8) {
                    if isAssigned {
                        // Sound Icon
                        if let sf = sfSymbol {
                            Image(systemName: sf)
                                .font(.system(size: 24))
                                .foregroundColor(themeColor)
                        } else if let em = emoji {
                            Text(em)
                                .font(.system(size: 26))
                        }
                        
                        // Sound Label
                        Text(name)
                            .font(.system(size: 11, weight: .bold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 4)
                    } else {
                        // Empty slot state
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.gray.opacity(0.5))
                        
                        Text("Add Sound")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Red Stop Overlay Button in Bottom Right Corner (Only when playing)
                if isPlaying {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                engine.stopSound(id: id)
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 20, height: 20)
                                        .shadow(radius: 2)
                                    
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(6)
                        }
                    }
                }
            }
            .frame(height: 100)
        }
        .buttonStyle(PlainButtonStyle())
        // Native macOS Right Click Context Menu
        .contextMenu {
            if isAssigned {
                Toggle(isOn: Binding(
                    get: { self.isLooping },
                    set: { self.engine.setLooping(id: self.id, looping: $0) }
                )) {
                    Text("Loop Sound")
                }
                
                Button(role: .destructive) {
                    engine.stopSound(id: id)
                } label: {
                    Label("Stop Sound", systemImage: "stop.fill")
                }
            }
        }
    }
}

// MARK: - Tab Views

struct SoundGridView: View {
    let title: String
    let sounds: [SoundDefinition]
    let themeColor: Color
    @ObservedObject var engine: SoundboardAudioEngine
    
    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .padding(.horizontal)
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(sounds) { sound in
                        SoundButton(
                            id: sound.id,
                            name: sound.name,
                            emoji: nil,
                            sfSymbol: sound.sfSymbol,
                            path: sound.relativePath,
                            themeColor: themeColor,
                            engine: engine
                        )
                    }
                }
                .padding()
            }
        }
        .padding(.top)
    }
}

// MARK: - Custom Slots Sheet Dialog

struct CustomSlotEditSheet: View {
    @Binding var isPresented: Bool
    let slotId: Int
    let currentConfig: CustomSlotConfig
    let onSave: (CustomSlotConfig) -> Void
    
    @State private var name: String = ""
    @State private var selectedPath: String = ""
    @State private var selectedEmoji: String = "🎵"
    
    let emojis = ["⚔️", "🛡️", "🐉", "🔥", "⛈️", "🏹", "🎺", "🐺", "🦁", "🐴", "🐶", "🐱", "🐔", "🐄", "🦗", "🐒", "🎵", "🔊", "📣", "💥"]
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Assign Sound to Slot \(slotId + 1)")
                .font(.system(size: 16, weight: .bold))
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Sound Display Name:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Enter display name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Audio File:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    TextField("No file selected", text: $selectedPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(true)
                    
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        panel.allowedContentTypes = [.audio]
                        
                        if panel.runModal() == .OK {
                            if let url = panel.url {
                                selectedPath = url.path
                                if name.isEmpty {
                                    name = url.deletingPathExtension().lastPathComponent
                                }
                            }
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose Icon Emoji:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(emojis, id: \.self) { emoji in
                            Text(emoji)
                                .font(.system(size: 22))
                                .padding(6)
                                .background(selectedEmoji == emoji ? Color.blue.opacity(0.2) : Color.clear)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedEmoji == emoji ? Color.blue : Color.clear, lineWidth: 1.5)
                                )
                                .onTapGesture {
                                    selectedEmoji = emoji
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    guard !selectedPath.isEmpty else { return }
                    let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalName = newName.isEmpty ? "Sound \(slotId + 1)" : newName
                    
                    let config = CustomSlotConfig(
                        id: slotId,
                        name: finalName,
                        filePath: selectedPath,
                        emoji: selectedEmoji,
                        isLooping: currentConfig.isLooping
                    )
                    onSave(config)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPath.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(width: 420)
        .onAppear {
            name = currentConfig.name ?? ""
            selectedPath = currentConfig.filePath ?? ""
            selectedEmoji = currentConfig.emoji ?? "🎵"
        }
    }
}

// MARK: - Custom Page Grid View

struct CustomGridView: View {
    @ObservedObject var engine: SoundboardAudioEngine
    @Binding var slots: [CustomSlotConfig]
    
    @State private var editingSlot: Int? = nil
    @State private var showingEditSheet = false
    
    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Personal Board")
                .font(.system(size: 22, weight: .bold))
                .padding(.horizontal)
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<9, id: \.self) { index in
                        let slot = slots[index]
                        
                        SoundButton(
                            id: "custom_\(index)",
                            name: slot.displayName,
                            emoji: slot.activeEmoji,
                            sfSymbol: nil,
                            path: slot.filePath,
                            themeColor: .orange,
                            engine: engine,
                            onClickAdd: {
                                editingSlot = index
                                showingEditSheet = true
                            }
                        )
                        .contextMenu {
                            if slot.filePath != nil {
                                Toggle(isOn: Binding(
                                    get: { self.engine.isLooping(id: "custom_\(index)") },
                                    set: { self.engine.setLooping(id: "custom_\(index)", looping: $0) }
                                )) {
                                    Text("Loop Sound")
                                }
                                
                                Button("Edit / Replace...") {
                                    editingSlot = index
                                    showingEditSheet = true
                                }
                                
                                Button("Rename...") {
                                    renamePrompt(index: index)
                                }
                                
                                Button(role: .destructive) {
                                    clearSlot(index: index)
                                } label: {
                                    Label("Clear Slot", systemImage: "trash")
                                }
                            } else {
                                Button("Assign Sound...") {
                                    editingSlot = index
                                    showingEditSheet = true
                                }
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                clearAllSlots()
                            } label: {
                                Label("Clear All Slots", systemImage: "trash.slash.fill")
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .padding(.top)
        .sheet(isPresented: $showingEditSheet) {
            if let slotIdx = editingSlot {
                CustomSlotEditSheet(
                    isPresented: $showingEditSheet,
                    slotId: slotIdx,
                    currentConfig: slots[slotIdx],
                    onSave: { newConfig in
                        slots[slotIdx] = newConfig
                        saveCustomConfigs()
                        
                        // Sync loop state to engine
                        engine.setLooping(id: "custom_\(slotIdx)", looping: newConfig.isLooping)
                    }
                )
            }
        }
    }
    
    private func saveCustomConfigs() {
        if let encoded = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(encoded, forKey: "customSlotsConfig")
        }
    }
    
    private func clearSlot(index: Int) {
        engine.stopSound(id: "custom_\(index)")
        slots[index] = CustomSlotConfig(id: index)
        saveCustomConfigs()
    }
    
    private func clearAllSlots() {
        let alert = NSAlert()
        alert.messageText = "Confirm Clear All Slots"
        alert.informativeText = "Are you sure you want to clear all custom slots? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Yes, Clear All")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            for i in 0..<9 {
                engine.stopSound(id: "custom_\(i)")
                slots[i] = CustomSlotConfig(id: i)
            }
            saveCustomConfigs()
        }
    }
    
    private func renamePrompt(index: Int) {
        let alert = NSAlert()
        alert.messageText = "Rename Sound"
        alert.informativeText = "Enter a new name for this custom sound:"
        alert.alertStyle = .informational
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = slots[index].name ?? ""
        alert.accessoryView = input
        
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty {
                slots[index].name = newName
                saveCustomConfigs()
            }
        }
    }
}

// MARK: - Main Application Root Layout

struct MainView: View {
    @StateObject private var engine = SoundboardAudioEngine()
    @State private var selectedTab: SidebarTab = .presets
    @State private var customSlots: [CustomSlotConfig] = []
    
    // Grid sound lists corresponding exactly to C# presets
    let presets = [
        SoundDefinition(id: "preset_0", name: "Sword Slash", relativePath: "sounds/presets/sword.wav", sfSymbol: "shield.fill"),
        SoundDefinition(id: "preset_1", name: "Barry Short Screech", relativePath: "sounds/presets/monkey_scream_short.wav", sfSymbol: "hare.fill"),
        SoundDefinition(id: "preset_2", name: "Barry Long Screech", relativePath: "sounds/presets/monkey_scream_long.wav", sfSymbol: "tortoise.fill"),
        SoundDefinition(id: "preset_3", name: "Wolf Growl", relativePath: "sounds/presets/wolf_growl.wav", sfSymbol: "safari.fill"),
        SoundDefinition(id: "preset_4", name: "Trumpet", relativePath: "sounds/presets/fail_trumpet.wav", sfSymbol: "music.note"),
        SoundDefinition(id: "preset_5", name: "Arrow", relativePath: "sounds/presets/arrow_whizz.wav", sfSymbol: "paperplane.fill"),
        SoundDefinition(id: "preset_6", name: "Dragon Roar", relativePath: "sounds/presets/dragon_roar.wav", sfSymbol: "flame.fill"),
        SoundDefinition(id: "preset_7", name: "Dragon Breathe Fire", relativePath: "sounds/presets/dragon_breathing_fire.wav", sfSymbol: "smoke.fill"),
        SoundDefinition(id: "preset_8", name: "Dragon Stomp", relativePath: "sounds/presets/dragon_stomp.wav", sfSymbol: "bolt.fill")
    ]
    
    let animals = [
        SoundDefinition(id: "animal_0", name: "Dog", relativePath: "sounds/animals/dog_bark.wav", sfSymbol: "dog.fill"),
        SoundDefinition(id: "animal_1", name: "Meow", relativePath: "sounds/animals/meow.wav", sfSymbol: "cat.fill"),
        SoundDefinition(id: "animal_2", name: "Rooster", relativePath: "sounds/animals/rooster.wav", sfSymbol: "bird.fill"),
        SoundDefinition(id: "animal_3", name: "Lion", relativePath: "sounds/animals/lion_roar.wav", sfSymbol: "pawprint.fill"),
        SoundDefinition(id: "animal_4", name: "Moo", relativePath: "sounds/animals/leaf.fill", sfSymbol: "pawprint.fill"),
        SoundDefinition(id: "animal_5", name: "Crickets", relativePath: "sounds/animals/crickets.wav", sfSymbol: "ant.fill"),
        SoundDefinition(id: "animal_6", name: "Wolf Howl", relativePath: "sounds/animals/wolf_howl.wav", sfSymbol: "moon.stars.fill"),
        SoundDefinition(id: "animal_7", name: "Horse Gallop", relativePath: "sounds/animals/horse_gallop.wav", sfSymbol: "figure.walk"),
        SoundDefinition(id: "animal_8", name: "Horse Neigh", relativePath: "sounds/animals/horse_neigh.wav", sfSymbol: "sparkles")
    ]
    
    var body: some View {
        NavigationSplitView {
            // Sidebar List Navigation
            List(SidebarTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 160)
            
            // Bottom utility area inside the Sidebar
            Spacer()
            
            VStack(spacing: 8) {
                // Real-time equalizer visual feedback
                EqualizerView(isAnimating: engine.isAnySoundPlaying)
                
                Divider()
                    .padding(.horizontal, 4)
                
                // Volume slider & stop controls
                HStack(spacing: 10) {
                    Image(systemName: engine.masterVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                        .frame(width: 16)
                        .onTapGesture {
                            engine.masterVolume = engine.masterVolume == 0 ? 0.8 : 0
                        }
                    
                    Slider(value: $engine.masterVolume, in: 0...1, step: 0.05)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    
                    Text("\(Int(engine.masterVolume * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
                .padding(.horizontal, 8)
                
                // Global Circular stop all button
                Button(action: {
                    engine.stopAllSounds()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                        Text("Stop All")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 16)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(16)
                    .shadow(color: Color.red.opacity(0.3), radius: 2)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 4)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            
        } detail: {
            // Main workspace content grid
            Group {
                switch selectedTab {
                case .presets:
                    SoundGridView(
                        title: "⚔️ Medieval Presets",
                        sounds: presets,
                        themeColor: Color.amberPrimary,
                        engine: engine
                    )
                case .animals:
                    SoundGridView(
                        title: "🐾 Animal Kingdom",
                        sounds: animals,
                        themeColor: Color.emeraldPrimary,
                        engine: engine
                    )
                case .custom:
                    CustomGridView(
                        engine: engine,
                        slots: $customSlots
                    )
                }
            }
            .background(.ultraThinMaterial)
            .frame(minWidth: 420)
        }
        .frame(minWidth: 700, minHeight: 480)
        .onAppear {
            loadCustomConfigsOnStartup()
        }
    }
    
    // Load custom configuration slots from UserDefaults
    private func loadCustomConfigsOnStartup() {
        if let saved = UserDefaults.standard.data(forKey: "customSlotsConfig"),
           let decoded = try? JSONDecoder().decode([CustomSlotConfig].self, from: saved) {
            self.customSlots = decoded
            
            // Re-sync all saved loop configurations to the engine
            for slot in decoded {
                if slot.filePath != nil {
                    engine.setLooping(id: "custom_\(slot.id)", looping: slot.isLooping)
                }
            }
        } else {
            // Seed 9 blank custom slots on first execution
            self.customSlots = (0..<9).map { CustomSlotConfig(id: $0) }
        }
    }
}

// MARK: - Color Extension Helpers

extension Color {
    static let amberPrimary = Color(red: 0.76, green: 0.52, blue: 0.08)
    static let emeraldPrimary = Color(red: 0.12, green: 0.53, blue: 0.31)
}

// MARK: - App Delegate & Main Definition

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct SoundboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(.dark) // Lock beautiful premium dark mode
        }
        .windowStyle(TitleBarWindowStyle())
        .windowToolbarStyle(UnifiedWindowToolbarStyle())
    }
}
