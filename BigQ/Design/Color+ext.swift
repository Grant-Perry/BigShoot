   //
   //  Color+Ext.swift
   //  BigRoll
   //
   //  Created by Grant Perry on 10/24/2026
   //

import SwiftUI


extension Color {


   init(rgb: Int...) {
	  if rgb.count == 3 {
		 self.init(red: Double(rgb[0]) / 255.0, green: Double(rgb[1]) / 255.0, blue: Double(rgb[2]) / 255.0)
	  } else {
		 self.init(red: 1.0, green: 0.5, blue: 1.0)
	  }
   }

	  /// Toggle palette: `true` = cpMuted* (default), `false` = cp* (normal/brighter). Set to switch.
   enum Palette {
	  static var muted: Bool = true
   }

   static let gpDesignGold               = Color(#colorLiteral(red: 0.7998082638, green: 0.6508761048, blue: 0.3491310477, alpha: 1))
	  /// Bottom-corner bloom on the iOS workspace mesh. Brand gold reads too warm
	  /// behind full-screen crew content, so the scene stays in the blues.
   static let gpDesignAzure              = Color(#colorLiteral(red: 0.06, green: 0.30, blue: 0.58, alpha: 1))

	  // MARK: - Liquid Glass pane tokens (BigLine)

	  /// Specular highlight wash on frosted panes.
   static let gpGlassFillHighlight       = Color(#colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1))
	  /// Drop shadow under floating glass.
   static let gpGlassShadow              = Color(#colorLiteral(red: 0.0, green: 0.0, blue: 0.0, alpha: 1))
	  /// Active stroke on glass cards (data / live).
   static let gpGlassActive              = Color(#colorLiteral(red: 0.20, green: 0.85, blue: 0.40, alpha: 1))
	  /// Power / emphasis stroke on glass cards.
   static let gpGlassPower               = Color(#colorLiteral(red: 0.9764705896, green: 0.850980401, blue: 0.5490196347, alpha: 1))

	  /// Scene-depth orbs (BigLine bokeh technique) — differently sized/colored blobs drifting
	  /// behind glass scenes so portal-frost cards have something to visibly refract.
   static let gpGlassBokehOrange         = Color(red: 0.94, green: 0.52, blue: 0.24)
   static let gpGlassBokehViolet         = Color(red: 0.55, green: 0.40, blue: 0.86)
   static let gpGlassBokehBlue           = Color(red: 0.30, green: 0.58, blue: 0.92)
   static let gpGlassBokehSky            = Color(red: 0.42, green: 0.74, blue: 0.94)
   static let gpGlassBokehGold           = Color(red: 0.86, green: 0.72, blue: 0.38)
   static let gpGlassBokehRose           = Color(red: 0.86, green: 0.46, blue: 0.56)

   static let gpProductionComplete       = Color(#colorLiteral(red: 0.9372549057, green: 0.3490196168, blue: 0.1921568662, alpha: 1))
   static let gpProductionOpen           = Color(#colorLiteral(red: 0.3911147745, green: 0.8800172018, blue: 0.2343971767, alpha: 1))

	  /// Softer card borders — full status colors read too loud at 2pt stroke.
   static let gpProductionOpenBorder     = gpProductionOpen.opacity(0.42)
   static let gpProductionCompleteBorder = gpProductionComplete.opacity(0.42)



   static let gpPastelMint               = Color(#colorLiteral(red: 0.816, green: 1, blue: 0.647, alpha: 1))
   static let gpGreen                    = Color(#colorLiteral(red: 0.6198272109, green: 0.6509014368, blue: 0.4784618616, alpha: 1))
   static let gpMinty                    = Color(#colorLiteral(red: 0.5960784314, green: 1, blue: 0.5960784314, alpha: 1))
   static let gpFlatGreen                = Color(#colorLiteral(red: 0.03852885208, green: 0.6235294342, blue: 0.3622174664, alpha: 1))
	  /// Soft teal for selected-plan glow — complements warm gold, reads well on dark
   static let gpActivePlanGlow           = Color(#colorLiteral(red: 0.35, green: 0.65, blue: 0.62, alpha: 1))

   static let gpArmyGreen                = Color(#colorLiteral(red: 0.4392156863, green: 0.4352941176, blue: 0.1803921569, alpha: 1))
   static let gpOrange                   = Color(#colorLiteral(red: 1, green: 0.6470588235, blue: 0, alpha: 1))
   static let gpPink                     = Color(#colorLiteral(red: 1, green: 0.4117647059, blue: 0.7058823529, alpha: 1))
   static let gpPurple                   = Color(#colorLiteral(red: 0.5568627715, green: 0.3529411852, blue: 0.9686274529, alpha: 1))
   static let gpDkPurple                 = Color(#colorLiteral(red: 0.3647058904, green: 0.06666667014, blue: 0.9686274529, alpha: 1))
   static let gpRed                      = Color(#colorLiteral(red: 0.9254902005, green: 0.2352941185, blue: 0.1019607857, alpha: 1))


	  // Hilight colors
   static let gpHiGreen                  = Color(#colorLiteral(red: 0.3911147745, green: 0.8800172018, blue: 0.2343971767, alpha: 1))
   static let gpHiMinty                  = Color(#colorLiteral(red: 0.5960784314, green: 1, blue: 0.5960784314, alpha: 1))
   static let gpHiRedPink                = Color(#colorLiteral(red: 1, green: 0.1857388616, blue: 0.3251032516, alpha: 1))
   static let gpHiOrange                 = Color(#colorLiteral(red: 0.9372549057, green: 0.3490196168, blue: 0.1921568662, alpha: 1))
   static let gpHiMintYellow             = Color(#colorLiteral(red: 0.816, green: 1, blue: 0.647, alpha: 1))
   static let gpHiYellow                 = Color(#colorLiteral(red: 0.9764705896, green: 0.850980401, blue: 0.5490196347, alpha: 1))
   static let gpHiBlue                   = Color(#colorLiteral(red: 0.4620226622, green: 0.8382837176, blue: 1, alpha: 1))
   static let gpHiLtBlue                 = Color(#colorLiteral(red: 0.2392156869, green: 0.6745098233, blue: 0.9686274529, alpha: 1))
   static let gpHiDkBlue                 = Color(#colorLiteral(red: 0.1019607857, green: 0.2784313858, blue: 0.400000006, alpha: 1))
   static let gpHiPurple                 = Color(#colorLiteral(red: 0.5568627715, green: 0.3529411852, blue: 0.9686274529, alpha: 1))
   static let gpHiCream                  = Color(#colorLiteral(red: 0.9450985789, green: 0.9490197301, blue: 0.8000027537, alpha: 1))
   static let gpHiFav                    = Color(#colorLiteral(red: 0.80610038, green: 0.9686274529, blue: 0.7690739287, alpha: 1))
   static let gpSideBarHi                = Color(#colorLiteral(red: 0, green: 0.2927228212, blue: 0.9990779757, alpha: 1))
   static let gpSideBarLow               = Color(#colorLiteral(red: 0.0008281979826, green: 0.5638359189, blue: 0.991630733, alpha: 1))

	  // Accounting
   static let gpPositive                 = Color(#colorLiteral(red: 0.80610038, green: 0.9686274529, blue: 0.7690739287, alpha: 1))
   static let gpWarning                  = Color(#colorLiteral(red: 0.9764705896, green: 0.850980401, blue: 0.5490196347, alpha: 1))
   static let gpNegative                 = Color(#colorLiteral(red: 1, green: 0.4932718873, blue: 0.4739984274, alpha: 1))
	  /// Watch / caution wash — cream gold into brand gold.
   static var gpWarningGradient: LinearGradient {
	  LinearGradient(
		 colors: [gpWarning, gpDesignGold],
		 startPoint: .topLeading,
		 endPoint: .bottomTrailing
	  )
   }
	  /// Warning / outflow wash — coral into hot pink-red. Do not fade `.orange` on dark glass (reads as brown).
   static var gpNegativeGradient: LinearGradient {
	  LinearGradient(
		 colors: [gpNegative, gpHiRedPink],
		 startPoint: .topLeading,
		 endPoint: .bottomTrailing
	  )
   }

	  /// Designed two-stop wash for brand status tokens (`.gpWarning.gradient`, `.gpNegative.gradient`).
   var gradient: LinearGradient {
	  if self == .gpWarning { return Self.gpWarningGradient }
	  if self == .gpNegative { return Self.gpNegativeGradient }
	  if self == .gpCompanyPlum { return Self.gpCompanyGradient }
	  return LinearGradient(
		 colors: [self, self.opacity(0.62)],
		 startPoint: .topLeading,
		 endPoint: .bottomTrailing
	  )
   }


	  /// App-wide white for strokes and accents
   static let gpWhite                    = Color.white
   static let gpRedPitch                 = Color(#colorLiteral(red: 0.9254902005, green: 0.2352941185, blue: 0.1019607857, alpha: 1))
   static let gpSelected                 = Color(#colorLiteral(red: 0.5843137503, green: 0.8235294223, blue: 0.4196078479, alpha: 1))
   static let gpSelectedFav              = Color(#colorLiteral(red: 0.2392156869, green: 0.6745098233, blue: 0.9686274529, alpha: 1))
   static let gpRedPink                  = Color(#colorLiteral(red: 1, green: 0.1857388616, blue: 0.3251032516, alpha: 1))
   static let gpYellowD                  = Color(#colorLiteral(red: 0.7254902124, green: 0.4784313738, blue: 0.09803921729, alpha: 1))
   static let gpTan                      = Color(#colorLiteral(red: 0.4483810227, green: 0.3676018354, blue: 0.1985318112, alpha: 1))
   static let gpGold                     = Color(#colorLiteral(red: 0.6001003385, green: 0.4902321696, blue: 0.2627026737, alpha: 1))
   static let gpYellow                   = Color(#colorLiteral(red: 0.7166176741, green: 0.631458951, blue: 0.3852883836, alpha: 1))
   static let gpChkBox                   = Color(#colorLiteral(red: 0.545, green: 0.765, blue: 0.290, alpha: 1))


	  /// Bright airport-style yellow for gate pills on dark cards.
   static let gpGatePill                 = Color(#colorLiteral(red: 1, green: 0.8235294118, blue: 0.09803921569, alpha: 1))
   static let gpDeltaPurple              = Color(#colorLiteral(red: 0.5450980392, green: 0.1019607843, blue: 0.2901960784, alpha: 1))
   static let gpMaroon                   = Color(#colorLiteral(red: 0.4392156863, green: 0.1803921569, blue: 0.3137254902, alpha: 1))
	  /// Vendor-company chrome — same hue as the plum swatch, lifted so icons and
	  /// selected pills read on dark glass. System `.purple` reads as candy pink.
   static let gpCompanyPlum              = Color(#colorLiteral(red: 0.4862745098, green: 0.1411764706, blue: 0.3411764706, alpha: 1)) // #7C2457

	  /// Eyedropped company wash — deep plum → midnight.
   static let gpCompanyPlumDeep          = Color(#colorLiteral(red: 0.2745098039, green: 0.07843137255, blue: 0.1921568627, alpha: 1)) // #461431
   static let gpCompanyMidnight          = Color(#colorLiteral(red: 0.2078431373, green: 0.08235294118, blue: 0.1529411765, alpha: 1)) // #351427
   static var gpCompanyGradient: LinearGradient {
	  LinearGradient(
		 colors: [gpCompanyPlum, gpCompanyPlumDeep, gpCompanyMidnight],
		 startPoint: .topLeading,
		 endPoint: .bottomTrailing
	  )
   }
   static let gpBlueDark                 = Color(#colorLiteral(red: 0.05882352963, green: 0.180392161, blue: 0.2470588237, alpha: 1))
   static let gpBlueDarkL                = Color(#colorLiteral(red: 0.08346207272, green: 0.1920862778, blue: 0.2470588237, alpha: 1))
   static let gpBlueLight                = Color(#colorLiteral(red: 0.1411764771, green: 0.3960784376, blue: 0.5647059083, alpha: 1))
   static let gpBlue                     = Color(#colorLiteral(red: 0.4620226622, green: 0.8382837176, blue: 1, alpha: 1))
   static let gpLtBlue                   = Color(#colorLiteral(red: 0.7, green: 0.9, blue: 1, alpha: 1))

   static let gpDark1                    = Color(#colorLiteral(red: 0.1378855407, green: 0.1486340761, blue: 0.1635932028, alpha: 1))
   static let gpDark2                    = Color(#colorLiteral(red: 0.1298420429, green: 0.1298461258, blue: 0.1298439503, alpha: 1))

   static let gpCalToday                 = Color(#colorLiteral(red: 0.7450980544, green: 0.1568627506, blue: 0.07450980693, alpha: 1))
   static let gpPostBot                  = Color(#colorLiteral(red: 0.9686274529, green: 0.78039217, blue: 0.3450980484, alpha: 1))

   static let gpCurrentTop               = Color(#colorLiteral(red: 0.2392156869, green: 0.6745098233, blue: 0.9686274529, alpha: 1))
   static let gpCurrentBot               = Color(#colorLiteral(red: 0.3128006691, green: 0.4008095726, blue: 0.6235075593, alpha: 1))

   static let gpScheduledTop             = Color(#colorLiteral(red: 0.3156160096, green: 0.6235294342, blue: 0.5034397076, alpha: 1))
   static let gpMoney					 = Color(#colorLiteral(red: 0.7829285786, green: 1, blue: 0.8622121677, alpha: 1))
   static let gpScheduledBot             = Color(#colorLiteral(red: 0.03852885208, green: 0.6235294342, blue: 0.3622174664, alpha: 1))

   static let gpFinalTop                 = Color(#colorLiteral(red: 0.4196078431, green: 0.2901960784, blue: 0.4745098039, alpha: 1))
   static let gpLivePlayHead             = Color(#colorLiteral(red: 0.4196078431, green: 0.2901960784, blue: 0.4745098039, alpha: 1))

   static let gpBreadcrumb               = Color(#colorLiteral(red: 0.768627451, green: 0.6078431373, blue: 0.8588235294, alpha: 1))
   static let gpGuidedRoute              = Color(#colorLiteral(red: 0.2392156869, green: 0.6745098233, blue: 0.9686274529, alpha: 1))


	  /// Calculate luminance using WCAG formula
   func luminance() -> Double {
	  var red: CGFloat = 0
	  var green: CGFloat = 0
	  var blue: CGFloat = 0

#if os(macOS)
		 // Catalog/dynamic colors (.accentColor, .secondary, system colors) throw from
		 // getRed:green:blue:alpha: — convert to sRGB first, and treat anything that
		 // still can't be resolved as mid grey rather than taking down the window.
	  guard let platformColor = NSColor(self).usingColorSpace(.sRGB) else { return 0.5 }
	  platformColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
#else
	  let platformColor = UIColor(self)
	  guard platformColor.getRed(&red, green: &green, blue: &blue, alpha: nil) else { return 0.5 }
#endif

		 // Apply gamma correction according to WCAG
	  func adjustComponent(_ component: CGFloat) -> CGFloat {
		 return component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
	  }

	  let adjRed = adjustComponent(red)
	  let adjGreen = adjustComponent(green)
	  let adjBlue = adjustComponent(blue)

		 // WCAG luminance formula
	  return 0.2126 * Double(adjRed) + 0.7152 * Double(adjGreen) + 0.0722 * Double(adjBlue)
   }

	  /// Determine if color is light based on luminance
   func isLight() -> Bool {
	  return luminance() > 0.5
   }

	  /// Return appropriate contrasting text color (black or white)
   func adaptedTextColor() -> Color {
	  return isLight() ? Color.black : Color.white
   }

	  /// Calculate WCAG contrast ratio against another color
   func contrastRatio(against color: Color) -> Double {
	  let luminance1 = self.luminance()
	  let luminance2 = color.luminance()
	  let lighter = max(luminance1, luminance2)
	  let darker = min(luminance1, luminance2)
	  return (lighter + 0.05) / (darker + 0.05)
   }

   func interpolated(with color: Color, by factor: Double) -> Color {
	  let factor = max(0, min(1, factor)) // Clamp factor between 0 and 1

#if os(macOS)
		 // Catalog/dynamic colors crash getRed:green:blue:alpha:; convert to sRGB first
	  let nc1 = NSColor(self)
	  let nc2 = NSColor(color)
	  guard let c1 = nc1.usingColorSpace(.sRGB),
			let c2 = nc2.usingColorSpace(.sRGB) else {
		 return factor < 0.5 ? self : color
	  }
#else
	  let c1 = UIColor(self)
	  let c2 = UIColor(color)
#endif

	  var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
	  var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0

	  c1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
	  c2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

	  let r = r1 + (r2 - r1) * factor
	  let g = g1 + (g2 - g1) * factor
	  let b = b1 + (b2 - b1) * factor
	  let a = a1 + (a2 - a1) * factor

	  return Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
   }

	  // 🔥 DRY: Moved from DraftWarRoomApp.swift
	  /// Get RGB components of color for interpolation and manipulation
   var components: (red: Double, green: Double, blue: Double, alpha: Double) {
#if os(macOS)
	  let platformColor = NSColor(self)
#else
	  let platformColor = UIColor(self)
#endif
	  var red: CGFloat = 0
	  var green: CGFloat = 0
	  var blue: CGFloat = 0
	  var alpha: CGFloat = 0
	  platformColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
	  return (Double(red), Double(green), Double(blue), Double(alpha))
   }

	  /// Hex string for persistence (e.g. "#FF5733")
   var hexString: String {
	  let c = components
	  let r = Int(c.red * 255)
	  let g = Int(c.green * 255)
	  let b = Int(c.blue * 255)
	  return String(format: "#%02X%02X%02X", r, g, b)
   }

	  /// Create Color from hex string ("#RRGGBB" or "RRGGBB")
   init?(hex: String) {
	  var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
	  if hex.hasPrefix("#") { hex.removeFirst() }
	  guard hex.count == 6, let rgb = Int(hex, radix: 16) else { return nil }
	  let r = Double((rgb >> 16) & 0xFF) / 255
	  let g = Double((rgb >> 8) & 0xFF) / 255
	  let b = Double(rgb & 0xFF) / 255
	  self.init(red: r, green: g, blue: b)
   }
}
