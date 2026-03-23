#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


def env_or_default(name: str, default: str) -> str:
    value = os.environ.get(name)
    return value if value not in (None, "") else default


CONFIG_PATH = env_or_default(
    "KMAN_CONFIG_PATH",
    str(Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "kanshi" / "config"),
)
NIRI_CMD = env_or_default("KMAN_NIRI", "niri")
KANSHICTL_CMD = env_or_default("KMAN_KANSHICTL", "kanshictl")
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp")
CACHE_PATH = RUNTIME_DIR / "noctalia-kanshi-manager-state.json"
RELOAD_ONCE_STAMP = RUNTIME_DIR / "noctalia-kanshi-manager-reload.stamp"


@dataclass
class ProfileBlock:
    pid: str
    name: str | None
    display_name: str
    switchable: bool
    body: str
    start: int
    end: int


def run_command(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True, check=check)


def ok(message: str, **extra: Any) -> None:
    payload = {"ok": True, "message": message}
    payload.update(extra)
    print(json.dumps(payload))


def fail(message: str, *, exit_code: int = 1, **extra: Any) -> None:
    payload = {"ok": False, "message": message}
    payload.update(extra)
    print(json.dumps(payload))
    raise SystemExit(exit_code)


def load_cache() -> dict[str, Any]:
    try:
        if CACHE_PATH.exists():
            data = json.loads(CACHE_PATH.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return data
    except Exception:
        pass
    return {}


def save_cache(data: dict[str, Any]) -> None:
    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    CACHE_PATH.write_text(json.dumps(data), encoding="utf-8")


def read_config_text() -> str:
    path = Path(CONFIG_PATH)
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8")


def write_config_text(text: str) -> None:
    path = Path(CONFIG_PATH)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


HEADER_RE = re.compile(r"^profile(?:\s+([^\s{]+))?\s*$", re.DOTALL)


def parse_profiles(text: str) -> list[ProfileBlock]:
    profiles: list[ProfileBlock] = []
    i = 0
    n = len(text)
    top_level = 0
    count = 0

    while i < n:
        ch = text[i]

        if ch == "#":
            newline = text.find("\n", i)
            i = n if newline == -1 else newline + 1
            continue

        if ch == '"':
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == '"':
                    i += 1
                    break
                i += 1
            continue

        if ch == "{":
            top_level += 1
            i += 1
            continue

        if ch == "}":
            top_level = max(0, top_level - 1)
            i += 1
            continue

        if top_level == 0 and text.startswith("profile", i):
            before_ok = i == 0 or not (text[i - 1].isalnum() or text[i - 1] == "_")
            after_idx = i + 7
            after_ok = after_idx >= n or text[after_idx].isspace() or text[after_idx] == "{"
            if before_ok and after_ok:
                brace_idx = text.find("{", after_idx)
                if brace_idx == -1:
                    break
                header = text[i:brace_idx].strip()
                header_match = HEADER_RE.match(header)
                if not header_match:
                    i += 7
                    continue
                name = header_match.group(1)

                depth = 1
                j = brace_idx + 1
                while j < n and depth > 0:
                    current = text[j]
                    if current == '"':
                        j += 1
                        while j < n:
                            if text[j] == "\\":
                                j += 2
                                continue
                            if text[j] == '"':
                                j += 1
                                break
                            j += 1
                        continue
                    if current == "#":
                        newline = text.find("\n", j)
                        j = n if newline == -1 else newline + 1
                        continue
                    if current == "{":
                        depth += 1
                    elif current == "}":
                        depth -= 1
                    j += 1

                end = j
                if depth != 0:
                    break

                body = text[brace_idx + 1 : end - 1].strip("\n")
                count += 1
                display_name = name if name else f"Unnamed profile {count}"
                profiles.append(
                    ProfileBlock(
                        pid=f"profile-{count}",
                        name=name,
                        display_name=display_name,
                        switchable=bool(name),
                        body=body,
                        start=i,
                        end=end,
                    )
                )
                i = end
                continue

        i += 1

    return profiles


def validate_profile_name(name: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9._-]+", name):
        fail("Invalid profile name. Use letters, numbers, dot, underscore, or dash.")


def render_profile_block(name: str, body: str) -> str:
    validate_profile_name(name)
    normalized_body = body.rstrip()
    if normalized_body:
        return f"profile {name} {{\n{normalized_body}\n}}\n"
    return f"profile {name} {{\n}}\n"


def replace_profile(text: str, profile_id: str, new_name: str, body: str) -> str:
    profiles = parse_profiles(text)
    block = render_profile_block(new_name, body)

    if not profile_id:
        trimmed = text.rstrip()
        if trimmed:
            return trimmed + "\n\n" + block
        return block

    for profile in profiles:
        if profile.pid == profile_id:
            return text[: profile.start] + block + text[profile.end :]

    fail("Profile to update was not found")
    return text


def delete_profile(text: str, profile_id: str) -> str:
    profiles = parse_profiles(text)
    for profile in profiles:
        if profile.pid == profile_id:
            new_text = text[: profile.start] + text[profile.end :]
            return re.sub(r"\n{3,}", "\n\n", new_text).lstrip("\n")
    fail("Profile to delete was not found")
    return text


def floatish(value: Any) -> str | None:
    if value is None:
        return None
    try:
        as_float = float(value)
    except Exception:
        return str(value)
    if abs(as_float - round(as_float)) < 0.0005:
        return str(int(round(as_float)))
    return f"{as_float:.3f}".rstrip("0").rstrip(".")


def mode_string(mode: dict[str, Any] | None) -> str | None:
    if not mode:
        return None
    width = mode.get("width")
    height = mode.get("height")
    refresh = mode.get("refresh")
    if refresh is None:
        refresh = mode.get("refresh_rate")
    if refresh is None:
        refresh = mode.get("refreshRate")
    if width and height:
        if refresh is not None:
            try:
                refresh_value = float(refresh)
                if refresh_value > 1000:
                    refresh_value = refresh_value / 1000.0
                refresh_text = f"{refresh_value:.3f}".rstrip("0").rstrip(".")
                return f"{width}x{height}@{refresh_text}"
            except Exception:
                return f"{width}x{height}@{refresh}"
        return f"{width}x{height}"
    return None


def logical_value(logical: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in logical:
            return logical[key]
    return None


def current_mode_from_output(output: dict[str, Any]) -> dict[str, Any] | None:
    modes = output.get("modes") or []
    for mode in modes:
        if mode.get("is_current") or mode.get("isCurrent"):
            return mode
    return None


def preferred_mode_from_output(output: dict[str, Any]) -> dict[str, Any] | None:
    modes = output.get("modes") or []
    for mode in modes:
        if mode.get("is_preferred") or mode.get("isPreferred"):
            return mode
    return None


def normalize_outputs(raw_outputs: Any) -> list[dict[str, Any]]:
    if not isinstance(raw_outputs, dict):
        return []

    monitors: list[dict[str, Any]] = []
    for name, output in raw_outputs.items():
        if not isinstance(output, dict):
            continue

        logical = output.get("logical") or {}
        current_mode = current_mode_from_output(output)
        preferred_mode = preferred_mode_from_output(output)
        current_mode_text = mode_string(current_mode)
        preferred_mode_text = mode_string(preferred_mode)

        enabled = True
        if output.get("off") is True or output.get("is_off") is True or output.get("enabled") is False:
            enabled = False
        elif current_mode is None and logical_value(logical, "width") in (None, 0):
            enabled = False

        make = output.get("make") or output.get("manufacturer") or output.get("brand") or ""
        model = output.get("model") or ""
        serial = output.get("serial") or ""
        transform = output.get("transform") or logical_value(logical, "transform") or "normal"
        scale = logical_value(logical, "scale")
        pos_x = logical_value(logical, "x", "pos_x", "left")
        pos_y = logical_value(logical, "y", "pos_y", "top")
        logical_w = logical_value(logical, "width")
        logical_h = logical_value(logical, "height")

        summary_parts = []
        if make or model:
            summary_parts.append(" ".join(part for part in [make, model, serial] if part).strip())
        if current_mode_text:
            summary_parts.append(current_mode_text)
        elif preferred_mode_text:
            summary_parts.append(f"preferred {preferred_mode_text}")

        details_parts = []
        if pos_x is not None and pos_y is not None:
            details_parts.append(f"pos {pos_x},{pos_y}")
        if logical_w is not None and logical_h is not None:
            details_parts.append(f"logical {logical_w}x{logical_h}")
        if scale is not None:
            details_parts.append(f"scale {floatish(scale)}")
        if transform:
            details_parts.append(f"transform {transform}")

        monitors.append(
            {
                "name": name,
                "enabled": enabled,
                "summary": " · ".join(part for part in summary_parts if part) or name,
                "details": " · ".join(part for part in details_parts if part),
                "current_mode": current_mode_text or "",
                "preferred_mode": preferred_mode_text or "",
                "make": make,
                "model": model,
                "serial": serial,
                "scale": floatish(scale) or "",
                "transform": transform,
                "logical_x": pos_x,
                "logical_y": pos_y,
                "logical_width": logical_w,
                "logical_height": logical_h,
            }
        )

    monitors.sort(key=lambda item: item["name"])
    return monitors


def render_current_profile_body(monitors: list[dict[str, Any]]) -> str:
    if not monitors:
        return ""

    lines: list[str] = []
    for monitor in monitors:
        name = monitor["name"]
        if monitor["enabled"]:
            parts = [f'    output "{name}" enable']
            mode = monitor.get("current_mode")
            if mode:
                parts.append(f"mode {mode}")
            x = monitor.get("logical_x")
            y = monitor.get("logical_y")
            if x is not None and y is not None:
                parts.append(f"position {x},{y}")
            scale = monitor.get("scale")
            if scale:
                parts.append(f"scale {scale}")
            transform = monitor.get("transform")
            if transform and transform != "normal":
                parts.append(f"transform {transform}")
            lines.append(" ".join(parts))
        else:
            lines.append(f'    output "{name}" disable')
    return "\n".join(lines)


def canonicalize_profile_body(body: str) -> str:
    body = re.sub(r"#.*", "", body)
    lines = []
    for raw_line in body.splitlines():
        line = " ".join(raw_line.strip().split())
        if line:
            lines.append(line)
    return "\n".join(lines)


def infer_active_profile_name(
    kanshi_status: str,
    profiles: list[ProfileBlock],
    current_profile_body: str,
    cache: dict[str, Any],
) -> tuple[str, str]:
    status = kanshi_status or ""
    patterns = [
        r"(?im)^\s*(?:active|current)\s+profile\s*[:=]\s*\"?([^\"\n]+)\"?\s*$",
        r"(?im)^\s*profile\s*[:=]\s*\"?([^\"\n]+)\"?\s*$",
        r"(?im)^\s*switched\s+to\s+profile\s+\"?([^\"\n]+)\"?\s*$",
    ]
    for pattern in patterns:
        match = re.search(pattern, status)
        if match:
            candidate = match.group(1).strip()
            if candidate:
                return candidate, "status"

    current_canonical = canonicalize_profile_body(current_profile_body)
    if current_canonical:
        for profile in profiles:
            if profile.name and canonicalize_profile_body(profile.body) == current_canonical:
                return profile.name, "layout-match"

    cached = str(cache.get("active_profile_name") or cache.get("last_switched_profile") or "").strip()
    if cached:
        return cached, "cache"

    return "", ""


def get_outputs() -> dict[str, Any]:
    completed = run_command([NIRI_CMD, "msg", "--json", "outputs"])
    stdout = completed.stdout.strip()
    return json.loads(stdout) if stdout else {}


def get_kanshi_status() -> str:
    completed = run_command([KANSHICTL_CMD, "status"], check=False)
    if completed.returncode != 0:
        return (completed.stderr or completed.stdout or "kanshictl status failed").strip()
    return completed.stdout.strip()


def build_state_payload() -> dict[str, Any]:
    errors: list[str] = []
    cache = load_cache()
    config_text = ""
    profiles: list[ProfileBlock] = []
    outputs: dict[str, Any] = {}
    kanshi_status = ""

    try:
        config_text = read_config_text()
        profiles = parse_profiles(config_text)
    except Exception as exc:  # pragma: no cover - best effort
        errors.append(f"Failed to read or parse kanshi config: {exc}")

    try:
        outputs = get_outputs()
    except Exception as exc:  # pragma: no cover - best effort
        errors.append(f"Failed to query Niri outputs: {exc}")

    try:
        kanshi_status = get_kanshi_status()
    except Exception as exc:  # pragma: no cover - best effort
        kanshi_status = ""
        errors.append(f"Failed to query kanshi status: {exc}")

    monitors = normalize_outputs(outputs)
    current_profile_body = render_current_profile_body(monitors)
    active_profile_name, active_profile_source = infer_active_profile_name(
        kanshi_status,
        profiles,
        current_profile_body,
        cache,
    )

    enabled_count = sum(1 for monitor in monitors if monitor.get("enabled"))

    payload = {
        "config_path": CONFIG_PATH,
        "profiles": [
            {
                "id": profile.pid,
                "name": profile.name or "",
                "display_name": profile.display_name,
                "switchable": profile.switchable,
                "body": profile.body,
            }
            for profile in profiles
        ],
        "monitors": monitors,
        "current_profile_body": current_profile_body,
        "kanshi_status": kanshi_status,
        "active_profile_name": active_profile_name,
        "active_profile_source": active_profile_source,
        "monitor_count": len(monitors),
        "enabled_monitor_count": enabled_count,
        "errors": errors,
    }

    next_cache = dict(cache)
    if active_profile_name:
        next_cache["active_profile_name"] = active_profile_name
    next_cache["last_monitor_count"] = len(monitors)
    next_cache["last_enabled_monitor_count"] = enabled_count
    save_cache(next_cache)

    return payload


def command_state() -> None:
    print(json.dumps(build_state_payload()))


def command_summary() -> None:
    payload = build_state_payload()
    active_profile_name = payload.get("active_profile_name") or "Displays"
    print(
        json.dumps(
            {
                "ok": True,
                "active_profile_name": active_profile_name,
                "monitor_count": payload.get("monitor_count", 0),
                "enabled_monitor_count": payload.get("enabled_monitor_count", 0),
            }
        )
    )


def command_save_profile(profile_id: str, new_name: str) -> None:
    body = os.environ.get("KMAN_BODY", "")
    text = read_config_text()
    updated = replace_profile(text, profile_id, new_name, body)
    write_config_text(updated)

    cache = load_cache()
    cache["active_profile_name"] = new_name
    save_cache(cache)
    ok("Profile saved", active_profile_name=new_name)


def command_delete_profile(profile_id: str) -> None:
    if not profile_id:
        fail("No profile selected")
    text = read_config_text()
    updated = delete_profile(text, profile_id)
    write_config_text(updated)
    ok("Profile deleted")


def command_switch_profile(name: str) -> None:
    validate_profile_name(name)
    completed = run_command([KANSHICTL_CMD, "switch", name], check=False)
    if completed.returncode != 0:
        fail((completed.stderr or completed.stdout or "kanshictl switch failed").strip())

    cache = load_cache()
    cache["active_profile_name"] = name
    cache["last_switched_profile"] = name
    save_cache(cache)
    ok(f"Switched to profile {name}", active_profile_name=name)


def perform_reload() -> subprocess.CompletedProcess[str]:
    return run_command([KANSHICTL_CMD, "reload"], check=False)


def command_reload() -> None:
    completed = perform_reload()
    if completed.returncode != 0:
        fail((completed.stderr or completed.stdout or "kanshictl reload failed").strip())
    ok("kanshi reloaded")


def command_reload_once() -> None:
    if RELOAD_ONCE_STAMP.exists():
        ok("Startup reload already done", skipped=True)
        return

    completed = perform_reload()
    if completed.returncode != 0:
        fail((completed.stderr or completed.stdout or "kanshictl reload failed").strip())

    RELOAD_ONCE_STAMP.parent.mkdir(parents=True, exist_ok=True)
    RELOAD_ONCE_STAMP.write_text("done\n", encoding="utf-8")
    ok("kanshi reloaded on startup")


def command_monitor(action: str, name: str) -> None:
    if action not in {"on", "off"}:
        fail("Unsupported monitor action")
    completed = run_command([NIRI_CMD, "msg", "output", name, action], check=False)
    if completed.returncode != 0:
        fail((completed.stderr or completed.stdout or f"Failed to turn {action} output").strip())
    ok(f"Output {name} turned {action}")


def main(argv: list[str]) -> None:
    if len(argv) < 2:
        fail("Missing command")

    command = argv[1]

    if command == "state":
        command_state()
        return
    if command == "summary":
        command_summary()
        return
    if command == "save-profile":
        if len(argv) < 4:
            fail("save-profile requires <profile-id> and <name>")
        command_save_profile(argv[2], argv[3])
        return
    if command == "delete-profile":
        if len(argv) < 3:
            fail("delete-profile requires <profile-id>")
        command_delete_profile(argv[2])
        return
    if command == "switch-profile":
        if len(argv) < 3:
            fail("switch-profile requires <name>")
        command_switch_profile(argv[2])
        return
    if command == "reload":
        command_reload()
        return
    if command == "reload-once":
        command_reload_once()
        return
    if command == "monitor-on":
        if len(argv) < 3:
            fail("monitor-on requires <name>")
        command_monitor("on", argv[2])
        return
    if command == "monitor-off":
        if len(argv) < 3:
            fail("monitor-off requires <name>")
        command_monitor("off", argv[2])
        return

    fail(f"Unknown command: {command}")


if __name__ == "__main__":
    main(sys.argv)
