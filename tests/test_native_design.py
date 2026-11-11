"""Check actual asset geometry and contrast; no Apple SDK/rendering claim."""

import hashlib
import json
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "ios/KMobile/Assets.xcassets"


def colors(name):
    result = {}
    for entry in json.loads(
        (ASSETS / (name + ".colorset") / "Contents.json").read_text()
    )["colors"]:
        mode = (
            "dark"
            if any(a["value"] == "dark" for a in entry.get("appearances", []))
            else "light"
        )
        c = entry["color"]["components"]
        result[mode] = tuple(float(c[k]) for k in ("red", "green", "blue"))
    return result


def contrast(a, b):
    def luminance(c):
        return sum(
            w * (v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4)
            for w, v in zip((0.2126, 0.7152, 0.0722), c)
        )

    lo, hi = sorted((luminance(a), luminance(b)))
    return (hi + 0.05) / (lo + 0.05)


class NativeDesignTests(unittest.TestCase):
    def test_text_and_semantic_colors_on_working_surfaces(self):
        for mode in ("light", "dark"):
            for surface in ("Canvas", "Surface"):
                for foreground in ("Ink", "MutedInk", "Success", "Caution", "Danger"):
                    with self.subTest(
                        mode=mode, surface=surface, foreground=foreground
                    ):
                        self.assertGreaterEqual(
                            contrast(colors(foreground)[mode], colors(surface)[mode]),
                            4.5,
                        )

    def test_all_accents_keep_readable_primary_labels_and_pressed_controls(self):
        for mode in ("light", "dark"):
            for name in (
                "AccentColor",
                "AccentIce",
                "AccentLilac",
                "AccentRose",
                "AccentAmber",
            ):
                accent = colors(name)[mode]
                with self.subTest(mode=mode, accent=name):
                    self.assertGreaterEqual(
                        contrast(accent, colors("OnAccent")[mode]), 4.5
                    )
                    for surface in ("Canvas", "Surface"):
                        background = colors(surface)[mode]
                        for opacity in (0, 0.06, 0.16):
                            mixed = tuple(
                                a * opacity + b * (1 - opacity)
                                for a, b in zip(accent, background)
                            )
                            self.assertGreaterEqual(contrast(accent, mixed), 4.5)

    def test_native_glyphs_are_vector_templates_with_recorded_provenance(self):
        record = json.loads((ROOT / "ios/design-provenance.json").read_text())
        for glyph in record["icons"]:
            folder = ASSETS / (glyph["asset"] + ".imageset")
            data = (folder / "icon.svg").read_bytes()
            svg = ET.fromstring(data)
            contents = json.loads((folder / "Contents.json").read_text())
            self.assertEqual(svg.attrib["viewBox"], "0 0 24 24")
            self.assertEqual(svg.attrib["stroke-width"], "1.5")
            self.assertEqual(svg.attrib["fill"], "none")
            self.assertEqual(
                contents["properties"]["template-rendering-intent"], "template"
            )
            self.assertTrue(contents["properties"]["preserves-vector-representation"])
            self.assertEqual(hashlib.sha256(data).hexdigest(), glyph["sha256"])
            self.assertNotIn(b"<image", data)
