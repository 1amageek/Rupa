import SwiftUI
import Testing
@testable import RupaUI

#if os(macOS)
import AppKit

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceSidebarSymbolsRenderWithinConsistentSlots() throws {
    _ = NSApplication.shared
    let names = [
        "folder", "cube", "cube.transparent", "pencil.and.outline", "ruler",
        "gearshape", "square.stack.3d.up", "square.grid.3x3", "eye", "eye.slash",
        "lock.fill", "lock.open", "ellipsis.circle", "ellipsis", "pause.circle",
        "square.stack.3d.down.right", "paintpalette", "checkmark.seal",
        "checkmark.seal.fill", "square.and.arrow.up"
    ]
    #expect(WorkspaceSidebarSymbol.pointSize == 13)
    #expect(WorkspaceSidebarSymbol.slotSize == 20)
    for name in names {
        #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
        for scheme in [ColorScheme.light, .dark] {
            for color in [Color.primary, .secondary, .white] {
                let renderer = ImageRenderer(content:
                    WorkspaceSidebarSymbol(systemName: name)
                        .foregroundStyle(color)
                        .environment(\.colorScheme, scheme)
                )
                renderer.scale = 2
                let image = try #require(renderer.cgImage)
                #expect(image.width == 40 && image.height == 40)
                let bitmap = NSBitmapImageRep(cgImage: image)
                var visiblePixels = 0
                var touchesEdge = false
                for y in 0..<image.height {
                    for x in 0..<image.width {
                        if let pixel = bitmap.colorAt(x: x, y: y), pixel.alphaComponent > 0.01 {
                            visiblePixels += 1
                            touchesEdge = touchesEdge || x == 0 || y == 0
                                || x == image.width - 1 || y == image.height - 1
                        }
                    }
                }
                #expect(visiblePixels > 0, "Empty symbol: \(name)")
                #expect(!touchesEdge, "Clipped symbol: \(name)")
            }
        }
    }
}
#endif

#if os(macOS)
@MainActor
@Test
func workspaceSidebarStateSymbolsShrinkGlyphsButKeepHitSlots() throws {
    for name in ["eye", "eye.slash", "lock.fill", "lock.open", "hourglass"] {
        var pixelCounts: [Int] = []
        for size in [11.0, 13.0] {
            let renderer = ImageRenderer(content:
                WorkspaceSidebarSymbol(systemName: name, size: size)
                    .foregroundStyle(.white)
            )
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            #expect(image.width == 40 && image.height == 40)
            let bitmap = NSBitmapImageRep(cgImage: image)
            var pixels = 0
            for y in 0..<image.height {
                for x in 0..<image.width {
                    if let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.1 {
                        pixels += 1
                    }
                }
            }
            pixelCounts.append(pixels)
        }
        #expect(pixelCounts[0] > 0 && pixelCounts[0] < pixelCounts[1], "Glyph did not shrink: \(name)")
    }
}
#endif
