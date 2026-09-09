#!/usr/bin/env python3
"""Validate the shared Copilot/OpenCode skill layout."""

from __future__ import annotations

import re
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SKILLS_ROOT = REPOSITORY_ROOT / "skills"
NAME_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
LINK_PATTERN = re.compile(r"\[[^\]]+\]\(([^)]+)\)")


def parse_frontmatter(path: Path) -> dict[str, str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "---":
        raise AssertionError(f"{path}: missing opening YAML frontmatter delimiter")

    try:
        end = lines.index("---", 1)
    except ValueError as exc:
        raise AssertionError(f"{path}: missing closing YAML frontmatter delimiter") from exc

    values: dict[str, str] = {}
    for line in lines[1:end]:
        if not line or line[0].isspace() or ":" not in line:
            continue
        key, value = line.split(":", 1)
        values[key.strip()] = value.strip().strip("\"'")
    return values


def validate_skill(skill_directory: Path) -> list[str]:
    errors: list[str] = []
    skill_path = skill_directory / "SKILL.md"
    if not skill_path.is_file():
        return [f"{skill_directory}: missing SKILL.md"]

    try:
        frontmatter = parse_frontmatter(skill_path)
    except AssertionError as exc:
        return [str(exc)]

    name = frontmatter.get("name", "")
    description = frontmatter.get("description", "")
    if name != skill_directory.name:
        errors.append(
            f"{skill_path}: frontmatter name '{name}' does not match directory"
        )
    if not NAME_PATTERN.fullmatch(name):
        errors.append(f"{skill_path}: name is not valid kebab-case")
    if not 1 <= len(description) <= 1024:
        errors.append(f"{skill_path}: description must contain 1-1024 characters")

    content = skill_path.read_text(encoding="utf-8")
    reference_links = [
        target
        for target in LINK_PATTERN.findall(content)
        if target.startswith("references/")
    ]
    references_directory = skill_directory / "references"
    if references_directory.is_dir() and not reference_links:
        errors.append(f"{skill_path}: references directory exists but is not linked")
    for target in reference_links:
        if not (skill_directory / target).is_file():
            errors.append(f"{skill_path}: broken reference link '{target}'")

    for markdown_path in skill_directory.rglob("*.md"):
        markdown = markdown_path.read_text(encoding="utf-8")
        for target in LINK_PATTERN.findall(markdown):
            if (
                "://" in target
                or target.startswith("#")
                or target.startswith("mailto:")
            ):
                continue
            relative_target = target.split("#", 1)[0]
            if relative_target and not (markdown_path.parent / relative_target).exists():
                errors.append(f"{markdown_path}: broken local link '{target}'")

    return errors


def main() -> int:
    errors: list[str] = []
    skill_directories = sorted(path for path in SKILLS_ROOT.iterdir() if path.is_dir())
    for skill_directory in skill_directories:
        errors.extend(validate_skill(skill_directory))

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(f"Validated {len(skill_directories)} shared skill definitions.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
