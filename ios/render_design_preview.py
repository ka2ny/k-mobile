#!/usr/bin/env python3
"""Review actual native palette/vector assets; requires rsvg-convert, not an iOS simulator."""

from pathlib import Path
import json, re, subprocess

root = Path(__file__).resolve().parents[1]
record = json.loads((root / "ios/design-provenance.json").read_text())
pal = record["palette"]
icons = record["icons"]
parts = [
    '<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="940" viewBox="0 0 1440 940">',
    '<rect width="1440" height="940" fill="#101213"/>',
    '<text x="40" y="42" fill="#d8dfd9" font-family="sans-serif" font-size="20">k-hole mobile / native cohesion</text>',
    '<text x="40" y="69" fill="#a6b0aa" font-family="sans-serif" font-size="13">Actual vector assets and palette tokens · component review, not simulator screenshots</text>',
]
for j, mode in enumerate(("light", "dark")):
    x = 24 + j * 708
    bg = pal["Canvas"][mode]
    surface = pal["Surface"][mode]
    ink = pal["Ink"][mode]
    muted = pal["MutedInk"][mode]
    accent = pal["AccentColor"][mode]
    parts.extend(
        [
            f'<rect x="{x}" y="96" width="684" height="820" rx="24" fill="{bg}"/>',
            f'<text x="{x + 28}" y="137" fill="{muted}" font-family="monospace" font-size="12">{mode.upper()} / GRAPHITE + SAGE</text>',
            f'<text x="{x + 28}" y="184" fill="{ink}" font-family="sans-serif" font-size="32">Your computer</text>',
            f'<text x="{x + 28}" y="214" fill="{muted}" font-family="sans-serif" font-size="15">Controls, files and agents from this phone.</text>',
        ]
    )
    for n, g in enumerate(icons):
        cx = x + 28 + (n % 6) * 105
        cy = 246 + (n // 6) * 105
        svg = (
            root / "ios/KMobile/Assets.xcassets" / f"{g['asset']}.imageset/icon.svg"
        ).read_text()
        inner = re.search(r"<svg[^>]*>(.*)</svg>", svg).group(1)
        parts.extend(
            [
                f'<rect x="{cx}" y="{cy}" width="94" height="92" rx="12" fill="{surface}"/>',
                f'<g transform="translate({cx + 29},{cy + 14}) scale(1.5)" fill="none" stroke="{accent if n in (0, 4, 8) else ink}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">{inner}</g>',
                f'<text x="{cx + 47}" y="{cy + 75}" text-anchor="middle" fill="{muted}" font-family="sans-serif" font-size="11">{g["name"]}</text>',
            ]
        )
    parts.extend(
        [
            f'<rect x="{x + 28}" y="480" width="628" height="164" rx="20" fill="{surface}" stroke="{pal["Border"][mode]}"/>',
            f'<text x="{x + 52}" y="518" fill="{ink}" font-family="sans-serif" font-size="21">Connect a computer</text>',
            f'<text x="{x + 52}" y="546" fill="{muted}" font-family="sans-serif" font-size="14">Use the address and PIN in desktop Settings → Remote.</text>',
            f'<rect x="{x + 52}" y="568" width="220" height="50" rx="12" fill="{accent}"/>',
            f'<text x="{x + 162}" y="599" text-anchor="middle" fill="{pal["OnAccent"][mode]}" font-family="sans-serif" font-size="16">+ Add connection</text>',
        ]
    )
    for k, name in enumerate(
        ("AccentColor", "AccentIce", "AccentLilac", "AccentRose", "AccentAmber")
    ):
        cx = x + 52 + k * 122
        color = pal[name][mode]
        parts.extend(
            [
                f'<circle cx="{cx + 18}" cy="698" r="14" fill="{color}"/>',
                f'<text x="{cx + 18}" y="731" text-anchor="middle" fill="{muted}" font-family="sans-serif" font-size="12">{["Sage", "Ice", "Lilac", "Rose", "Amber"][k]}</text>',
            ]
        )
    for k, (status, name) in enumerate(
        (("Success", "Connected"), ("Caution", "Needs attention"), ("Danger", "Failed"))
    ):
        cx = x + 42 + k * 202
        parts.extend(
            [
                f'<circle cx="{cx}" cy="783" r="4" fill="{pal[status][mode]}"/>',
                f'<text x="{cx + 14}" y="788" fill="{pal[status][mode]}" font-family="sans-serif" font-size="14">{name}</text>',
            ]
        )
    parts.append(
        f'<text x="{x + 28}" y="867" fill="{muted}" font-family="sans-serif" font-size="13">One stroke family · opaque working surfaces · status independent of accent</text>'
    )
parts.append("</svg>")
(root / "artifacts/cohesion").mkdir(parents=True, exist_ok=True)
out = root / "artifacts/cohesion/native-theme-board.svg"
out.write_text("\n".join(parts))
subprocess.run(
    ["rsvg-convert", str(out), "-o", str(out.with_suffix(".png"))], check=True
)
