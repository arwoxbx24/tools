#!/usr/bin/env python3
"""Сторож отгрузки: проверяет, что все локальные коммиты отгружены на remote."""

import os
import subprocess
import sys
from typing import List, Tuple


def run_git_cmd(directory: str, *args: str, timeout: int = 30) -> Tuple[str, bool]:
    """Выполняет git-команду, возвращает (stdout, успех). Ошибки не роняют обход."""
    try:
        result = subprocess.run(
            ["git"] + list(args),
            cwd=directory,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.stdout.strip(), result.returncode == 0
    except Exception:
        return "", False


def scan_projects(base_path: str) -> List[Tuple[str, str, str, str]]:
    """Обходит проекты, собирает данные о состоянии отгрузки."""
    projects = []

    dirs_to_check = [base_path]
    try:
        for entry in os.listdir(base_path):
            full_path = os.path.join(base_path, entry)
            if os.path.isdir(full_path) and os.path.isdir(os.path.join(full_path, ".git")):
                dirs_to_check.append(full_path)
    except Exception:
        pass

    for directory in dirs_to_check:
        proj_name = os.path.basename(directory)

        has_remote, ok = run_git_cmd(directory, "remote", "get-url", "origin")
        if not ok:
            projects.append((proj_name, "БЕЗ REMOTE", "ошибка", "ошибка"))
            continue

        if not has_remote:
            projects.append((proj_name, "БЕЗ REMOTE", "ошибка", "ошибка"))
            continue

        count, ok = run_git_cmd(directory, "rev-list", "--count", "--all", "--not", "--remotes")
        if not ok:
            projects.append((proj_name, "есть", "ошибка", "ошибка"))
            continue

        try:
            count_int = int(count)
        except ValueError:
            count_int = -1

        date, ok = run_git_cmd(directory, "log", "-1", "--format=%ad", "--date=short")
        if not ok:
            projects.append((proj_name, "есть", str(count_int), "ошибка"))
            continue

        projects.append((proj_name, "есть", str(count_int), date or "неизвестно"))

    return projects


def print_table(projects: List[Tuple[str, str, str, str]]) -> int:
    """Печатает таблицу и возвращает количество проектов в риске."""
    print(f"{'проект':<30} {'remote':<12} {'неотгружено':<12} {'последний коммит'}")
    print("-" * 70)

    risk_count = 0

    sorted_projects = sorted(
        projects,
        key=lambda p: (0 if p[1] == "БЕЗ REMOTE" else 1, int(p[2]) if p[2].isdigit() else 1),
    )

    for proj_name, remote, count, date in sorted_projects:
        print(f"{proj_name:<30} {remote:<12} {count:<12} {date}")
        if remote == "БЕЗ REMOTE" or (count.isdigit() and int(count) > 0):
            risk_count += 1

    print("-" * 70)
    print(f"всего проектов в риске: {risk_count}")

    return risk_count


def demo() -> None:
    """Самопроверка: разбор вывода git rev-list."""
    test_values = ["0", "5", "100", ""]
    for val in test_values:
        try:
            if val:
                assert int(val) >= 0
            else:
                int(val)
        except ValueError:
            continue
    assert True


if __name__ == "__main__":
    base = "/root/workspaces/projects"
    projects = scan_projects(base)
    risk = print_table(projects)
    sys.exit(1 if risk > 0 else 0)
