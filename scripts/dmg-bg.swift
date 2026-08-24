// Generates the installer backdrop (scripts/dmg-bg.tiff comes from this
// via sips resampling and tiffutil -cathidpicheck at 1x and 2x).
// Run: swift scripts/dmg-bg.swift  (expects the painting on the Desktop)
import AppKit
import CoreText

let painting = NSImage(contentsOf: URL(fileURLWithPath: NSString(string: "~/Desktop/caravaggios/1_the calling.jpg").expandingTildeInPath))!
for f in ["Archivo-ExtraBold.ttf"] {
    let url = URL(fileURLWithPath: "/Users/arjun/Documents/GitHub/chiaro/Sources/Chiaro/Resources/Fonts/\(f)")
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}

// Window content 660x500pt at 2x. Icons sit at y=250 with Finder's own
// labels under them (the convention); the labels land on baked plates whose
// mid-warm tone keeps both black (light mode) and white (dark mode) label
// text near 4.5:1.
let W: CGFloat = 1320, H: CGFloat = 1000
let out = NSImage(size: NSSize(width: W, height: H))
out.lockFocus()

let pw = painting.size.width, ph = painting.size.height
let scale = max(W / pw, H / ph)
let dw = pw * scale, dh = ph * scale
painting.draw(in: NSRect(x: (W - dw) / 2, y: (H - dh) * 0.4, width: dw, height: dh))
NSColor(red: 0x10/255, green: 0x0C/255, blue: 0x09/255, alpha: 0.70).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// Lit well behind the drop target: macOS 26 folder icons are dark adaptive
// glass and vanish on a dark ground without one.
let well = NSBezierPath(roundedRect: NSRect(x: 870, y: 280, width: 240, height: 240), xRadius: 44, yRadius: 44)
NSColor(white: 1, alpha: 0.11).setFill()
well.fill()
NSColor(white: 1, alpha: 0.22).setStroke()
well.lineWidth = 2
well.stroke()

// The claim up top, two lines like the site hero, then the drag hint —
// Finder paints its labels dark over background pictures in both modes,
// so those clip below the window and the artwork carries all the words.
let font = NSFont(name: "Archivo-ExtraBold", size: 56) ?? NSFont.systemFont(ofSize: 56, weight: .heavy)
let style = NSMutableParagraphStyle()
style.alignment = .center
style.lineHeightMultiple = 0.94
let hs = NSAttributedString(string: "The RAW editor\nyour agent can drive", attributes: [
    .font: font,
    .foregroundColor: NSColor(red: 0xF8/255, green: 0xF3/255, blue: 0xEC/255, alpha: 0.94),
    .kern: 56 * -0.032,
    .paragraphStyle: style,
])
let hSize = hs.size()
hs.draw(in: NSRect(x: (W - hSize.width) / 2, y: H - 130 - hSize.height, width: hSize.width, height: hSize.height))

let hintFont = NSFont(name: "Geist", size: 27) ?? NSFont.systemFont(ofSize: 27)
let hint = NSAttributedString(string: "Drag Chiaro into Applications to install", attributes: [
    .font: hintFont,
    .foregroundColor: NSColor(red: 0xF0/255, green: 0xE8/255, blue: 0xDE/255, alpha: 0.62),
])
let hintSize = hint.size()
hint.draw(at: NSPoint(x: (W - hintSize.width) / 2, y: H - 330 - hintSize.height / 2))

// The drag.
let arrow = NSBezierPath()
let ay: CGFloat = 400
arrow.move(to: NSPoint(x: 520, y: ay))
arrow.line(to: NSPoint(x: 790, y: ay))
arrow.move(to: NSPoint(x: 746, y: ay + 30))
arrow.line(to: NSPoint(x: 790, y: ay))
arrow.line(to: NSPoint(x: 746, y: ay - 30))
arrow.lineWidth = 6
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(white: 1, alpha: 0.35).setStroke()
arrow.stroke()

out.unlockFocus()
let rep = NSBitmapImageRep(data: out.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-arjun-Documents-GitHub-chiaro/a3268362-d019-4067-9e46-82107e01db7b/scratchpad/dmg-bg.png"))
print("ok")
