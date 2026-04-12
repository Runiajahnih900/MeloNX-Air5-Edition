//
//  RomFolderManager.swift
//  MeloNX
//
//  Created by Stossy11 on 31/07/2025.
//

import Foundation
import SwiftUI

let withSecurityScope = URL.BookmarkResolutionOptions(rawValue: 1 << 10)

class ROMFolderManager: ObservableObject {
    
    func normalizeFolderURL(url: URL) -> URL? {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }

        let parent = url.deletingLastPathComponent()
        var parentIsDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory), parentIsDirectory.boolValue {
            return parent
        }

        return nil
    }
    
    private let bookmarksKey = "ROMFolderManagerBookmarks"
    @Published var bookmarks: [Data] = [] {
        didSet {
            saveBookmarks()
        }
    }
    
    private init() {
        loadBookmarks()
    }
    
    static var shared = ROMFolderManager()
    
    func addFolder(url: URL) -> Bool {
        guard let folderURL = normalizeFolderURL(url: url) else {
            print("Failed to add folder: selected URL is not a valid directory")
            return false
        }

        let options = URL.BookmarkCreationOptions(rawValue: 1 << 11)

        do {
            let bookmark = try folderURL.bookmarkData(options: options,
                                                      includingResourceValuesForKeys: nil,
                                                      relativeTo: nil)
            bookmarks.append(bookmark)
            saveBookmarks()
            return true
        } catch {
            print("Failed to create bookmark: \(error)")
            return false
        }
    }
    
    func getUrl(from bookmark: Data) -> URL? {
        var isStale = false
        
        
        do {
            var url = try URL(
                resolvingBookmarkData: bookmark,
                options: withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                // Avoid mutating @Published bookmarks during SwiftUI render paths.
                // Stale bookmark refresh is handled lazily by addFolder/loadGames flows.
                print("Bookmark is stale for URL: \(url.path)")
            }
            
            return url
            
        } catch {
            print("Error resolving bookmark:", error)
            return nil
        }
    }

    
    
    func stopAccessingFolder(url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
    
    private func saveBookmarks() {
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }
    
    func loadBookmarks() {
        if let saved = UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] {
            bookmarks = saved
        } else if let saved = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] {
            bookmarks = Array(saved.values)
            saveBookmarks()
        }
    }
}
