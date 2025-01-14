//
//  MenuBarLyrics.swift
//
//  This file is part of LyricsX - https://github.com/ddddxxx/LyricsX
//  Copyright (C) 2017  Xander Deng. Licensed under GPLv3.
//

import Cocoa
import CombineX
import GenericID
import LyricsCore
import MusicPlayer
import OpenCC

class MenuBarLyrics: NSObject {
    
    static let shared = MenuBarLyrics()
    
    let statusItem: NSStatusItem
    var lyricsItem: NSStatusItem?
    var buttonImage = #imageLiteral(resourceName: "status_bar_icon")
    var buttonlength: CGFloat = 30
    
    private var screenLyrics = "" {
        didSet {
            DispatchQueue.main.async {
                self.updateStatusItem()
            }
        }
    }
    
    private var cancelBag = Set<AnyCancellable>()
    
    private override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        AppController.shared.$currentLyrics
            .combineLatest(AppController.shared.$currentLineIndex)
            .receive(on: DispatchQueue.lyricsDisplay.cx)
            .invoke(MenuBarLyrics.handleLyricsDisplay, weaklyOn: self)
            .store(in: &cancelBag)
        observeNotification(center: workspaceNC, name: NSWorkspace.didActivateApplicationNotification) { [unowned self] _ in self.updateStatusItem() }
        observeDefaults(keys: [.menuBarLyricsEnabled, .combinedMenubarLyrics], options: [.initial]) { [unowned self] in self.updateStatusItem() }
    }
    
    private func handleLyricsDisplay(event: (lyrics: Lyrics?, index: Int?)) {
        guard !defaults[.disableLyricsWhenPaused] || selectedPlayer.playbackState.isPlaying,
            let lyrics = event.lyrics,
            let index = event.index else {
            screenLyrics = ""
            return
        }
        var newScreenLyrics = lyrics.lines[index].content
        if let converter = ChineseConverter.shared, lyrics.metadata.language?.hasPrefix("zh") == true {
            newScreenLyrics = converter.convert(newScreenLyrics)
        }
        if newScreenLyrics == screenLyrics {
            return
        }
        screenLyrics = newScreenLyrics
    }
    
    @objc private func updateStatusItem() {
        guard defaults[.menuBarLyricsEnabled], !screenLyrics.isEmpty else {
            setImageStatusItem()
            lyricsItem = nil
            return
        }
        
        if defaults[.combinedMenubarLyrics] {
            updateCombinedStatusLyrics()
        } else {
            updateSeparateStatusLyrics()
        }
    }
    
    private func updateSeparateStatusLyrics() {
        setImageStatusItem()
        
        if lyricsItem == nil {
            lyricsItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            lyricsItem?.highlightMode = false
        }
        lyricsItem?.title = screenLyrics
    }
    
    private func updateCombinedStatusLyrics() {
        lyricsItem = nil
        
        setTextStatusItem(string: screenLyrics)
        if statusItem.isVisibe {
            return
        }
        
        // truncation
        var components = screenLyrics.components(options: [.byWords])
        while !components.isEmpty, !statusItem.isVisibe {
            components.removeLast()
            let proposed = components.joined() + "..."
            setTextStatusItem(string: proposed)
        }
    }
    
    private func setTextStatusItem(string: String) {
        statusItem.title = string
        statusItem.image = nil
        statusItem.length = NSStatusItem.variableLength
    }
    
    private func setImageStatusItem() {
        statusItem.title = ""
        statusItem.image = buttonImage
        statusItem.length = buttonlength
    }
}

// MARK: - Status Item Visibility

private extension NSStatusItem {
    
    var isVisibe: Bool {
        guard let buttonFrame = button?.frame,
            let frame = button?.window?.convertToScreen(buttonFrame) else {
                return false
        }
        
        let point = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            return false
        }
        let carbonPoint = CGPoint(x: point.x, y: screen.frame.height - point.y - 1)
        
        guard let element = AXUIElement.copyAt(position: carbonPoint) else {
            return false
        }
        
        return getpid() == element.pid
    }
}

private extension AXUIElement {
    
    static func copyAt(position: NSPoint) -> AXUIElement? {
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(position.x), Float(position.y), &element)
        guard error == .success else {
            return nil
        }
        return element
    }
    
    var pid: pid_t? {
        var pid: pid_t = 0
        let error = AXUIElementGetPid(self, &pid)
        guard error == .success else {
            return nil
        }
        return pid
    }
}

private extension String {
    
    func components(options: String.EnumerationOptions) -> [String] {
        var components: [String] = []
        let range = Range(uncheckedBounds: (startIndex, endIndex))
        enumerateSubstrings(in: range, options: options) { _, _, range, _ in
            components.append(String(self[range]))
        }
        return components
    }
}
