#!/usr/bin/env python3
"""Программный проверщик вёрстки пульта — headless, детерминировано, без ИИ.

Открывает URL или локальный файл на заданных ширинах, измеряет реальную
геометрию DOM через getBoundingClientRect и проверяет правила из YAML.

Usage:
    python3 tools/layout_check.py --url https://example.com/dashboard.html
    python3 tools/layout_check.py --file data/dashboard.html
    python3 tools/layout_check.py --file data/dashboard.html --json
    python3 tools/layout_check.py --file data/dashboard.html --widths 390,1440

Exit codes:
    0 — все правила прошли
    1 — найдены нарушения
    2 — ошибка аргументов / инфраструктуры
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from dataclasses import dataclass, asdict
from typing import Optional

import yaml

BASE = pathlib.Path(__file__).resolve().parent.parent

DEFAULT_RULES = BASE / "config" / "layout_rules.yaml"
# Страница ждёт networkidle не более N мс (на локальном файле быстро)
LOAD_TIMEOUT_MS = 15_000


@dataclass
class Violation:
    rule: str
    name: str
    selector: str
    width: int
    detail: str


# ──────────────────────────────────────────────────────────────────────────────
# Отдельные проверки
# ──────────────────────────────────────────────────────────────────────────────

def _check_no_horizontal_scroll(page, width: int) -> list[Violation]:
    scroll_w, client_w = page.evaluate(
        "() => [document.body.scrollWidth, document.documentElement.clientWidth]"
    )
    if scroll_w > client_w:
        return [Violation(
            rule="no_horizontal_scroll",
            name="Горизонтальный скролл",
            selector="body",
            width=width,
            detail=f"scrollWidth={scroll_w} > clientWidth={client_w}",
        )]
    return []


def _check_required_elements(page, rules: list[dict], width: int) -> list[Violation]:
    violations = []
    for rule in rules:
        selector = rule["selector"]
        text_contains = rule.get("text_contains")
        name = rule.get("name", selector)

        if text_contains:
            found = page.evaluate(
                """([sel, txt]) => {
                    const els = Array.from(document.querySelectorAll(sel));
                    return els.some(el => el.textContent.includes(txt));
                }""",
                [selector, text_contains],
            )
        else:
            found = page.evaluate(
                "(sel) => !!document.querySelector(sel)",
                selector,
            )

        if not found:
            detail = f'selector="{selector}"'
            if text_contains:
                detail += f', text_contains="{text_contains}"'
            violations.append(Violation(
                rule="required_elements",
                name=f"Обязательный элемент: {name}",
                selector=selector,
                width=width,
                detail=detail,
            ))
    return violations


def _check_no_overlap_pairs(page, pairs: list[dict], width: int) -> list[Violation]:
    violations = []
    for pair in pairs:
        allowed_viewports = pair.get("viewports")
        if allowed_viewports and width not in allowed_viewports:
            continue

        sel_a = pair["selector_a"]
        sel_b = pair["selector_b"]
        name = pair.get("name", f"{sel_a} / {sel_b}")

        result = page.evaluate(
            """([selA, selB]) => {
                const elA = document.querySelector(selA);
                const elB = document.querySelector(selB);
                if (!elA || !elB) return {skip: true};
                const a = elA.getBoundingClientRect();
                const b = elB.getBoundingClientRect();
                if (a.width === 0 || b.width === 0) return {skip: true};
                const overlaps = !(a.right <= b.left || b.right <= a.left ||
                                   a.bottom <= b.top  || b.bottom <= a.top);
                return {skip: false, overlaps,
                        aRect: {top:a.top,left:a.left,right:a.right,bottom:a.bottom},
                        bRect: {top:b.top,left:b.left,right:b.right,bottom:b.bottom}};
            }""",
            [sel_a, sel_b],
        )

        if result.get("skip"):
            continue
        if result["overlaps"]:
            a = result["aRect"]
            b = result["bRect"]
            violations.append(Violation(
                rule="no_overlap_pairs",
                name=f"Перекрытие: {name}",
                selector=f"{sel_a} + {sel_b}",
                width=width,
                detail=(
                    f"{sel_a}=[{a['left']:.0f},{a['top']:.0f},{a['right']:.0f},{a['bottom']:.0f}] "
                    f"{sel_b}=[{b['left']:.0f},{b['top']:.0f},{b['right']:.0f},{b['bottom']:.0f}]"
                ),
            ))
    return violations


def _check_week_grid_same_row(page, rule: dict, width: int) -> list[Violation]:
    allowed_viewports = rule.get("viewports")
    if allowed_viewports and width not in allowed_viewports:
        return []

    selector = rule["selector"]
    tolerance = rule.get("top_tolerance_px", 5)

    tops = page.evaluate(
        """([sel]) => {
            const els = Array.from(document.querySelectorAll(sel));
            return els
                .filter(el => el.getBoundingClientRect().width > 0)
                .map(el => el.getBoundingClientRect().top);
        }""",
        [selector],
    )

    if len(tops) < 2:
        return []

    spread = max(tops) - min(tops)
    if spread > tolerance:
        return [Violation(
            rule="week_grid_same_row",
            name="Колонки сетки недели в разных рядах",
            selector=selector,
            width=width,
            detail=f"top spread={spread:.1f}px > tolerance={tolerance}px, tops={[f'{t:.0f}' for t in tops]}",
        )]
    return []


def _check_min_column_width(page, rule: dict, width: int) -> list[Violation]:
    thresholds: dict = rule.get("thresholds", {})
    min_width = thresholds.get(width)
    if min_width is None:
        return []

    selector = rule["selector"]
    widths_found: list[float] = page.evaluate(
        """([sel]) => {
            return Array.from(document.querySelectorAll(sel))
                .map(el => el.getBoundingClientRect().width);
        }""",
        [selector],
    )

    violations = []
    narrow = [w for w in widths_found if w > 0 and w < min_width]
    if narrow:
        violations.append(Violation(
            rule="min_column_width",
            name=f"Колонка уже {min_width}px",
            selector=selector,
            width=width,
            detail=f"min_required={min_width}px, found_narrow={[f'{w:.0f}' for w in narrow]}",
        ))
    return violations


def _check_no_text_clip(page, selectors: list[str], width: int) -> list[Violation]:
    violations = []
    for selector in selectors:
        clipped: list[dict] = page.evaluate(
            """([sel]) => {
                return Array.from(document.querySelectorAll(sel))
                    .filter(el => el.scrollWidth > el.clientWidth + 2 && el.clientWidth > 0)
                    .map(el => ({scrollWidth: el.scrollWidth, clientWidth: el.clientWidth,
                                 text: el.textContent.trim().slice(0, 40)}));
            }""",
            [selector],
        )
        for c in clipped:
            violations.append(Violation(
                rule="no_text_clip",
                name="Текст обрезан",
                selector=selector,
                width=width,
                detail=f'scrollWidth={c["scrollWidth"]} > clientWidth={c["clientWidth"]}+2, text="{c["text"]}"',
            ))
    return violations


# ──────────────────────────────────────────────────────────────────────────────
# Основной запуск
# ──────────────────────────────────────────────────────────────────────────────

def check_viewport(page, rules: dict, width: int) -> list[Violation]:
    """Прогоняет все правила на уже открытой странице при данной ширине."""
    violations: list[Violation] = []

    if rules.get("no_horizontal_scroll", {}).get("enabled"):
        violations += _check_no_horizontal_scroll(page, width)

    if "required_elements" in rules:
        violations += _check_required_elements(page, rules["required_elements"], width)

    if "no_overlap_pairs" in rules:
        violations += _check_no_overlap_pairs(page, rules["no_overlap_pairs"], width)

    if "week_grid_same_row" in rules:
        violations += _check_week_grid_same_row(page, rules["week_grid_same_row"], width)

    if "min_column_width" in rules:
        violations += _check_min_column_width(page, rules["min_column_width"], width)

    if "no_text_clip" in rules:
        violations += _check_no_text_clip(page, rules["no_text_clip"]["selectors"], width)

    return violations


def run_checks(
    target: str,
    widths: list[int],
    rules: dict,
) -> list[Violation]:
    """target — URL или file:// path. Возвращает все нарушения."""
    from playwright.sync_api import sync_playwright

    all_violations: list[Violation] = []

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        for width in widths:
            page = browser.new_page(viewport={"width": width, "height": 900})
            try:
                page.goto(target, wait_until="domcontentloaded", timeout=LOAD_TIMEOUT_MS)
            except Exception as exc:
                all_violations.append(Violation(
                    rule="_infrastructure",
                    name="Ошибка загрузки страницы",
                    selector="",
                    width=width,
                    detail=str(exc),
                ))
                page.close()
                continue

            violations = check_viewport(page, rules, width)
            all_violations.extend(violations)
            page.close()
        browser.close()

    return all_violations


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Проверка вёрстки пульта (headless, детерминировано)"
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--url", help="URL страницы")
    group.add_argument("--file", help="Путь к локальному HTML-файлу")

    parser.add_argument(
        "--widths",
        default=None,
        help="Ширины через запятую, напр. 390,768,1440 (умолч. из rules YAML)",
    )
    parser.add_argument(
        "--rules",
        default=str(DEFAULT_RULES),
        help=f"Путь к layout_rules.yaml (умолч. {DEFAULT_RULES})",
    )
    parser.add_argument("--json", action="store_true", help="Вывод в JSON")
    args = parser.parse_args()

    # Загрузка правил
    rules_path = pathlib.Path(args.rules)
    if not rules_path.exists():
        print(f"[layout_check] ERROR: rules not found: {rules_path}", file=sys.stderr)
        return 2
    with rules_path.open() as f:
        rules: dict = yaml.safe_load(f)

    # Ширины
    if args.widths:
        try:
            widths = [int(w.strip()) for w in args.widths.split(",")]
        except ValueError:
            print("[layout_check] ERROR: --widths должны быть целыми числами", file=sys.stderr)
            return 2
    else:
        widths = rules.get("viewports", [390, 768, 1440])

    # Целевой URL
    if args.file:
        fp = pathlib.Path(args.file)
        if not fp.exists():
            print(f"[layout_check] ERROR: file not found: {fp}", file=sys.stderr)
            return 2
        target = fp.resolve().as_uri()
    else:
        target = args.url

    # Запуск
    violations = run_checks(target, widths, rules)

    if args.json:
        result = {
            "target": target,
            "widths": widths,
            "violations": [asdict(v) for v in violations],
            "passed": len(violations) == 0,
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        if violations:
            print(f"[layout_check] FAIL — {len(violations)} нарушений:")
            for v in violations:
                print(f"  ✗ [{v.width}px] {v.name}  selector={v.selector}  {v.detail}")
        else:
            print(f"[layout_check] OK — все правила прошли ({len(widths)} ширин: {widths})")

    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
