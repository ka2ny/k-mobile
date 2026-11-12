import UIKit
import XCTest

@testable import KMobile

final class DesignTests: XCTestCase {
    @MainActor
    func testEveryNativeGlyphLoadsFromTheCompiledAssetCatalog() throws {
        for glyph in MobileGlyph.allCases {
            let image = try XCTUnwrap(UIImage(named: glyph.asset), glyph.asset)
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertEqual(image.size.width, image.size.height)
        }
    }

    @MainActor
    func testAppearanceAssetsResolveInBothDeviceModes() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for name in [
                "Canvas", "Surface", "Ink", "MutedInk", "OnAccent", "Success", "Caution", "Danger",
                "AccentColor", "AccentIce", "AccentLilac", "AccentRose", "AccentAmber",
            ] {
                let color = try XCTUnwrap(UIColor(named: name), name).resolvedColor(with: traits)
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), name)
                XCTAssertEqual(alpha, 1, name)
            }
        }
    }
}
