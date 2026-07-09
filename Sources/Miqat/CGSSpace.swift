//
//  CGSSpace.swift
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Original source: https://github.com/avaidyam/Parrot/
// Via Boring.Notch (TheBoredTeam/boring.notch), NotchSpaceManager.
//
// ⚠️ Использует приватный CoreGraphics/SkyLight API. Годится для прямой
// раздачи .app; в Mac App Store такое не пропустят. Поэтому весь файл
// компилируется ТОЛЬКО в обычной сборке — в App Store-сборке (флаг APPSTORE)
// он пустой, и приватных символов CGS в бинаре не остаётся.

#if !APPSTORE
import AppKit

/// Обёртка над приватным Spaces API: создаёт «пространство», в которое можно
/// положить окно, чтобы оно показывалось на всех рабочих столах и full-screen.
public final class CGSSpace {
    private let identifier: CGSSpaceID

    public var windows: Set<NSWindow> = [] {
        didSet {
            let remove = oldValue.subtracting(self.windows)
            let add = self.windows.subtracting(oldValue)

            CGSRemoveWindowsFromSpaces(_CGSDefaultConnection(),
                                       remove.map { $0.windowNumber } as NSArray,
                                       [self.identifier])
            CGSAddWindowsToSpaces(_CGSDefaultConnection(),
                                  add.map { $0.windowNumber } as NSArray,
                                  [self.identifier])
        }
    }

    /// Созданные `CGSSpace` ОБЯЗАТЕЛЬНО должны деинициализироваться при выходе.
    public init(level: Int = 0) {
        let flag = 0x1 // должно быть 1, иначе Finder начинает рисовать иконки рабочего стола
        self.identifier = CGSSpaceCreate(_CGSDefaultConnection(), flag, nil)
        CGSSpaceSetAbsoluteLevel(_CGSDefaultConnection(), self.identifier, level)
        CGSShowSpaces(_CGSDefaultConnection(), [self.identifier])
    }

    deinit {
        CGSHideSpaces(_CGSDefaultConnection(), [self.identifier])
        CGSSpaceDestroy(_CGSDefaultConnection(), self.identifier)
    }
}

// MARK: - Приватные символы CGS
fileprivate typealias CGSConnectionID = UInt
fileprivate typealias CGSSpaceID = UInt64
@_silgen_name("_CGSDefaultConnection")
fileprivate func _CGSDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSSpaceCreate")
fileprivate func CGSSpaceCreate(_ cid: CGSConnectionID, _ unknown: Int, _ options: NSDictionary?) -> CGSSpaceID
@_silgen_name("CGSSpaceDestroy")
fileprivate func CGSSpaceDestroy(_ cid: CGSConnectionID, _ space: CGSSpaceID)
@_silgen_name("CGSSpaceSetAbsoluteLevel")
fileprivate func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int)
@_silgen_name("CGSAddWindowsToSpaces")
fileprivate func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSRemoveWindowsFromSpaces")
fileprivate func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSHideSpaces")
fileprivate func CGSHideSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
@_silgen_name("CGSShowSpaces")
fileprivate func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
#endif
