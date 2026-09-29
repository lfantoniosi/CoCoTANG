#!/usr/bin/env python3
"""Summarize the routed clock frequencies from Gowin's timing report."""

import re
import sys
from html import unescape
from pathlib import Path


def fail(message):
    print(f"timing: {message}", file=sys.stderr)
    return 2


def main():
    report = Path(sys.argv[1]) if len(sys.argv) == 2 else None
    if report is None or not report.is_file():
        return fail("missing routed report; run 'make rebuild' first")

    page = report.read_text(encoding="utf-8")
    summary = re.search(
        r'<a\s+name="Max_Frequency_Report"[^>]*>.*?</a>.*?<table[^>]*>(.*?)</table>',
        page,
        re.IGNORECASE | re.DOTALL,
    )
    if summary is None:
        return fail(f"Max Frequency Summary not found in {report}")

    rows = []
    for row_html in re.findall(r"<tr[^>]*>(.*?)</tr>", summary.group(1), re.IGNORECASE | re.DOTALL):
        cells = [
            unescape(re.sub(r"<[^>]+>", "", cell)).strip()
            for cell in re.findall(r"<td[^>]*>(.*?)</td>", row_html, re.IGNORECASE | re.DOTALL)
        ]
        if len(cells) < 4:
            continue
        required = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)\s*\(MHz\)", cells[2])
        actual = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)\s*\(MHz\)", cells[3])
        if required is None or actual is None:
            return fail(f"unrecognized frequency in row {cells[0]} of {report}")
        rows.append((cells[1], float(required.group(1)), float(actual.group(1))))

    if not rows:
        return fail(f"no clock frequencies found in {report}")

    print(f"Routed timing: {report}")
    print(f"{'Clock':<16} {'Target MHz':>11} {'Actual MHz':>11} {'Margin MHz':>11}  Result")
    failing = 0
    for clock, target, actual in rows:
        passed = actual >= target
        failing += not passed
        print(f"{clock:<16} {target:11.3f} {actual:11.3f} {actual - target:+11.3f}  {'PASS' if passed else 'FAIL'}")
    print(f"{failing} of {len(rows)} clocks miss timing" if failing else "All clocks meet timing")
    return 1 if failing else 0


if __name__ == "__main__":
    sys.exit(main())
