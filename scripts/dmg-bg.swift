// Generates the installer backdrop master PNG (2x). scripts/dmg-bg.tiff is
// then cut from it:
//   swift scripts/dmg-bg.swift <painting.jpg> [out.png]
//   sips -z 1000 1320 out.png --out /tmp/bg-2x.png
//   sips -z 500 660 out.png --out /tmp/bg-1x.png
//   sips -s dpiHeight 72 -s dpiWidth 72 /tmp/bg-1x.png
//   sips -s dpiHeight 144 -s dpiWidth 144 /tmp/bg-2x.png
//   tiffutil -cathidpicheck /tmp/bg-1x.png /tmp/bg-2x.png -out scripts/dmg-bg.tiff
// The shipped artwork uses Caravaggio's The Calling of Saint Matthew (public
// domain); any sufficiently dark painting works.
import AppKit
import CoreText

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: swift scripts/dmg-bg.swift <painting.jpg> [out.png]\n", stderr)
    exit(1)
}
let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let outPath = args.count >= 3 ? args[2] : "/tmp/dmg-bg-master.png"
guard let painting = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    fputs("could not read painting at \(args[1])\n", stderr)
    exit(1)
}
let fontsDir = repoRoot.appendingPathComponent("Sources/Chiaro/Resources/Fonts")
for f in ["Archivo-ExtraBold.ttf", "Geist-Regular.otf"] {
    CTFontManagerRegisterFontsForURL(fontsDir.appendingPathComponent(f) as CFURL, .process, nil)
}

// Window content 660x500pt, drawn 2x. Icons sit at y=250 in the window with
// Finder's own labels under them; every word here is in the artwork so it
// stays white in either appearance.
let W: CGFloat = 1320, H: CGFloat = 1000
let out = NSImage(size: NSSize(width: W, height: H))
out.lockFocus()

let pw = painting.size.width, ph = painting.size.height
let scale = max(W / pw, H / ph)
let dw = pw * scale, dh = ph * scale
painting.draw(in: NSRect(x: (W - dw) / 2, y: (H - dh) * 0.40, width: dw, height: dh))
NSColor(red: 0x10/255, green: 0x0C/255, blue: 0x09/255, alpha: 0.70).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// Lit well behind the drop target: macOS folder icons are dark adaptive
// glass and vanish on a dark ground without one.
let well = NSBezierPath(roundedRect: NSRect(x: 870, y: 280, width: 240, height: 240), xRadius: 44, yRadius: 44)
NSColor(white: 1, alpha: 0.11).setFill()
well.fill()
NSColor(white: 1, alpha: 0.22).setStroke()
well.lineWidth = 2
well.stroke()

// The claim, two lines like the site hero, then the drag hint.
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

let hintFont = NSFont(name: "Geist Regular", size: 27) ?? NSFont.systemFont(ofSize: 27)
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
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
