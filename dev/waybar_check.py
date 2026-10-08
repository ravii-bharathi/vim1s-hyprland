#!/usr/bin/env python3
"""waybar_check.py — validate the modular waybar config without running waybar.

    python3 -I dev/waybar_check.py waybar/config.jsonc

Checks (all things waybar itself only reports at runtime, or silently ignores):
  * every .jsonc file parses (// and /* */ comments allowed, as waybar allows)
  * every "include" entry exists, resolved like waybar does with WAYBAR_CONFIG_DIR=<config dir>
  * every module named in modules-left/center/right is defined by some included file
  * no module is defined twice (waybar keeps the FIRST definition, so a duplicate is dead config)
  * defined-but-unused modules are reported as warnings
Exit status 0 = clean, 1 = errors.
"""
import json
import os
import sys


def strip_jsonc(text: str) -> str:
    """Remove // and /* */ comments that are not inside JSON strings."""
    out, i, n = [], 0, len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j == -1 else j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            if j == -1:
                raise ValueError("unterminated /* comment")
            i = j + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def load(path: str):
    with open(path, encoding="utf-8") as fh:
        return json.loads(strip_jsonc(fh.read()))


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    main_path = sys.argv[1]
    base = os.path.dirname(os.path.abspath(main_path))
    errors, warnings = [], []

    try:
        cfg = load(main_path)
    except (OSError, ValueError) as e:
        print(f"waybar_check: {main_path}: {e}", file=sys.stderr)
        return 1
    if not isinstance(cfg, dict):
        print("waybar_check: expected a single bar object (multi-bar arrays not used here)", file=sys.stderr)
        return 1

    layout = [m for key in ("modules-left", "modules-center", "modules-right") for m in cfg.get(key, [])]
    defined = {}  # module name -> file that defines it first

    includes = cfg.get("include", [])
    if isinstance(includes, str):
        includes = [includes]
    for inc in includes:
        path = inc if os.path.isabs(inc) else os.path.join(base, inc)
        if not os.path.isfile(path):
            errors.append(f'include "{inc}" not found (looked for {path})')
            continue
        try:
            part = load(path)
        except ValueError as e:
            errors.append(f"{inc}: JSON error: {e}")
            continue
        for key in part:
            if key in defined:
                errors.append(f'module "{key}" defined in {inc} AND {defined[key]} — waybar keeps only the first')
            else:
                defined[key] = inc

    for key in cfg:
        if "/" in key or key in ("clock", "cpu", "memory", "network"):
            defined.setdefault(key, os.path.basename(main_path))

    for m in layout:
        if m not in defined:
            errors.append(f'module "{m}" is in the layout but not defined in any included file')
    for m in defined:
        if m not in layout:
            warnings.append(f'module "{m}" is defined ({defined[m]}) but not placed in modules-left/center/right')

    for w in warnings:
        print(f"waybar_check: warning: {w}")
    for e in errors:
        print(f"waybar_check: error: {e}", file=sys.stderr)
    if not errors:
        print(f"waybar_check: OK ({len(layout)} modules, {len(includes)} includes)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
