#!/bin/bash
# Verify bilingual documentation pairs, screenshot assets, and local links.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 - "$ROOT" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote

root = Path(sys.argv[1])
errors: list[str] = []

required_pairs = [
    "README.md",
    "CONTRIBUTING.md",
    "docs/README.md",
    "docs/CONNECTION_POLICY.md",
    "docs/PLATFORM_INTEGRATION.md",
    "docs/PRODUCT_DESIGN.md",
    "docs/IMPLEMENTATION.md",
    "docs/VERIFICATION.md",
    "docs/DECISIONS.md",
    "docs/CHANGELOG.md",
    "branding/IconComposer/README.md",
]

for relative in required_pairs:
    english = root / relative
    chinese = english.with_name(english.stem + ".zh-CN.md")
    if not english.is_file():
        errors.append(f"missing English document: {relative}")
    if not chinese.is_file():
        errors.append(f"missing Chinese document: {chinese.relative_to(root)}")

required_images = [
    "docs/screenshots/menu-bar-panel-en.png",
    "docs/screenshots/menu-bar-panel-zh.png",
    "docs/screenshots/settings-general-en.png",
    "docs/screenshots/settings-general-zh.png",
    "docs/screenshots/settings-devices-en.png",
    "docs/screenshots/settings-devices-zh.png",
    "docs/screenshots/settings-diagnostics-en.png",
    "docs/screenshots/settings-diagnostics-zh.png",
    "docs/screenshots/settings-about-en.png",
    "docs/screenshots/settings-about-zh.png",
    "docs/screenshots/icon-default-256.png",
    "docs/screenshots/icon-dark-256.png",
    "docs/screenshots/icon-tinted-light-200.png",
    "docs/screenshots/icon-clear-light-200.png",
]
for relative in required_images:
    path = root / relative
    if not path.is_file() or path.stat().st_size == 0:
        errors.append(f"missing or empty screenshot: {relative}")

markdown_files = [
    path
    for path in root.rglob("*.md")
    if not any(part in {".git", "build", "dist"} for part in path.parts)
]

link_patterns = [
    re.compile(r"\]\(\s*([^)\s]+)"),
    re.compile(r"""(?:src|href)\s*=\s*["']([^"']+)["']"""),
]

for document in sorted(markdown_files):
    text = document.read_text(encoding="utf-8")
    for line_number, line in enumerate(text.splitlines(), start=1):
        if "```" in line:
            continue
        for pattern in link_patterns:
            for match in pattern.finditer(line):
                target = match.group(1).strip().strip("<>")
                if not target or target.startswith(("#", "http://", "https://", "mailto:", "tel:")):
                    continue
                target = target.split("#", 1)[0].split("?", 1)[0]
                if not target:
                    continue
                path = Path(unquote(target))
                resolved = path if path.is_absolute() else document.parent / path
                if not resolved.exists():
                    errors.append(
                        f"{document.relative_to(root)}:{line_number}: missing local target {target}"
                    )

if errors:
    for error in errors:
        print(f"error: {error}")
    print(f"FAILED: {len(errors)} documentation issue(s)")
    raise SystemExit(1)

print(f"OK: {len(required_pairs)} bilingual pairs, {len(required_images)} screenshots, {len(markdown_files)} Markdown files")
PY
