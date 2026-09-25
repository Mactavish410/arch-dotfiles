#!/usr/bin/env python3
"""EndeavourOS voice/command assistant: Faster-Whisper + hyprctl + Ollama.

Graceful fallbacks when whisper / mic / ollama are unavailable so Hyprland
hotkeys never crash the session.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import wave
from pathlib import Path
from typing import Any, Optional
from urllib.error import URLError, HTTPError
from urllib.request import Request, urlopen

DOTFILES = Path(__file__).resolve().parent.parent
ENV_PATH = DOTFILES / ".env"


def load_env(path: Path = ENV_PATH) -> dict[str, str]:
    env: dict[str, str] = {}
    if not path.is_file():
        return env
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        val = val.strip().strip("'").strip('"')
        env[key] = val
        os.environ.setdefault(key, val)
    return env


def run_hyprctl(args: list[str], dry_run: bool = False) -> int:
    cmd = ["hyprctl", *args]
    if dry_run:
        print("DRY:", " ".join(cmd))
        return 0
    try:
        completed = subprocess.run(cmd, check=False, capture_output=True, text=True)
    except FileNotFoundError:
        print("hyprctl not found — are you in a Hyprland session?", file=sys.stderr)
        return 127
    if completed.stdout:
        print(completed.stdout.rstrip())
    if completed.returncode != 0 and completed.stderr:
        print(completed.stderr.rstrip(), file=sys.stderr)
    return completed.returncode


def parse_simple_command(text: str) -> Optional[list[str]]:
    """Map natural phrases (RU/EN) to hyprctl dispatch argv (without hyprctl)."""
    t = text.strip().lower()
    t = re.sub(r"[.!?,]+$", "", t)

    patterns: list[tuple[re.Pattern[str], list[str]]] = [
        (re.compile(r"^(workspace|рабочий стол|рабочий|ws)\s*(\d+)$"), ["dispatch", "workspace"]),
        (re.compile(r"^(перейди|открой|go to|switch to)\s+(workspace|рабочий стол)?\s*(\d+)$"), ["dispatch", "workspace"]),
        (re.compile(r"^(закрой окно|close window|killactive|kill active)$"), ["dispatch", "killactive"]),
        (re.compile(r"^(терминал|terminal|kitty)$"), ["dispatch", "exec", "kitty"]),
        (re.compile(r"^(браузер|browser|firefox)$"), ["dispatch", "exec", "firefox"]),
        (re.compile(r"^(launcher|рофи|rofi|menu)$"), ["dispatch", "exec", "rofi -show drun"]),
        (re.compile(r"^(lock|лок|заблокируй)$"), ["dispatch", "exec", "hyprlock"]),
        (re.compile(r"^(float|плавающее)$"), ["dispatch", "togglefloating"]),
        (re.compile(r"^(fullscreen|полный экран)$"), ["dispatch", "fullscreen"]),
    ]

    m = re.match(r"^(?:workspace|рабочий стол|рабочий|ws)\s*(\d+)$", t)
    if m:
        return ["dispatch", "workspace", m.group(1)]

    m = re.match(
        r"^(?:перейди|открой|go to|switch to)\s+(?:(?:на|to)\s+)?(?:workspace|рабочий стол)?\s*(\d+)$",
        t,
    )
    if m:
        return ["dispatch", "workspace", m.group(1)]

    for rx, base in patterns:
        m = rx.match(t)
        if not m:
            continue
        if base == ["dispatch", "workspace"]:
            # already handled above; keep for completeness
            digits = [g for g in m.groups() if g and g.isdigit()]
            if digits:
                return ["dispatch", "workspace", digits[-1]]
            continue
        return list(base)

    # "workspace 2" already covered; try bare number with keyword elsewhere
    m = re.search(r"(?:workspace|рабочий стол)\s*(\d+)", t)
    if m:
        return ["dispatch", "workspace", m.group(1)]

    if "закрой" in t and "окно" in t:
        return ["dispatch", "killactive"]
    if "close" in t and "window" in t:
        return ["dispatch", "killactive"]

    return None


def ollama_parse(text: str, host: str, model: str) -> Optional[list[str]]:
    """Ask Ollama to return JSON action: {\"dispatch\":[...]}."""
    prompt = (
        "You convert user voice commands for Hyprland into JSON only.\n"
        'Schema: {"dispatch":["workspace","2"]} or {"dispatch":["killactive"]}'
        ' or {"dispatch":["exec","kitty"]}.\n'
        "No markdown. Command: "
        + text
    )
    payload = {
        "model": model,
        "prompt": prompt,
        "stream": False,
        "format": "json",
    }
    url = host.rstrip("/") + "/api/generate"
    try:
        req = Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(req, timeout=20) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except (URLError, HTTPError, TimeoutError, json.JSONDecodeError) as exc:
        print(f"[ai] Ollama unavailable: {exc}", file=sys.stderr)
        return None

    raw = body.get("response", "")
    try:
        data: Any = json.loads(raw) if isinstance(raw, str) else raw
    except json.JSONDecodeError:
        # try extract object
        m = re.search(r"\{.*\}", raw, re.S)
        if not m:
            return None
        try:
            data = json.loads(m.group(0))
        except json.JSONDecodeError:
            return None

    if isinstance(data, dict) and "dispatch" in data:
        args = data["dispatch"]
        if isinstance(args, list) and all(isinstance(x, str) for x in args):
            return ["dispatch", *args] if args and args[0] != "dispatch" else list(args)
    return None


def record_audio(seconds: float, path: Path) -> bool:
    """Record mono wav via sox/arecord; write silence stub if tools missing."""
    if shutil.which("sox"):
        cmd = [
            "sox",
            "-d",
            "-r",
            "16000",
            "-c",
            "1",
            "-b",
            "16",
            str(path),
            "trim",
            "0",
            str(seconds),
        ]
        try:
            subprocess.run(cmd, check=True, capture_output=True)
            return True
        except (subprocess.CalledProcessError, FileNotFoundError) as exc:
            print(f"[ai] sox record failed: {exc}", file=sys.stderr)

    if shutil.which("arecord"):
        cmd = [
            "arecord",
            "-f",
            "S16_LE",
            "-r",
            "16000",
            "-c",
            "1",
            "-d",
            str(int(max(1, seconds))),
            str(path),
        ]
        try:
            subprocess.run(cmd, check=True, capture_output=True)
            return True
        except (subprocess.CalledProcessError, FileNotFoundError) as exc:
            print(f"[ai] arecord failed: {exc}", file=sys.stderr)

    # Silent stub so pipeline can continue in dry environments
    print("[ai] no recorder — writing silent wav stub", file=sys.stderr)
    nframes = int(16000 * max(0.1, seconds))
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(16000)
        wf.writeframes(b"\x00\x00" * nframes)
    return False


def transcribe_faster_whisper(audio_path: Path, model_size: str = "base") -> Optional[str]:
    try:
        from faster_whisper import WhisperModel  # type: ignore
    except ImportError:
        print(
            "[ai] faster-whisper not installed. "
            "Create venv and: pip install -r scripts/requirements-ai.txt",
            file=sys.stderr,
        )
        return None

    try:
        device = "cuda" if os.environ.get("CUDA_VISIBLE_DEVICES", "0") != "" else "cpu"
        compute = "float16" if device == "cuda" else "int8"
        try:
            model = WhisperModel(model_size, device=device, compute_type=compute)
        except Exception:
            model = WhisperModel(model_size, device="cpu", compute_type="int8")
        segments, _info = model.transcribe(str(audio_path), language=None)
        text = " ".join(seg.text.strip() for seg in segments).strip()
        return text or None
    except Exception as exc:  # noqa: BLE001 — never crash session
        print(f"[ai] Whisper transcription failed: {exc}", file=sys.stderr)
        return None


def resolve_action(text: str, use_ollama: bool) -> Optional[list[str]]:
    action = parse_simple_command(text)
    if action:
        return action
    if use_ollama:
        host = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
        model = os.environ.get("OLLAMA_MODEL", "qwen2.5-coder:7b")
        return ollama_parse(text, host, model)
    return None


def main(argv: Optional[list[str]] = None) -> int:
    load_env()
    parser = argparse.ArgumentParser(description="EndeavourOS Hyprland AI assistant")
    parser.add_argument("--text", "-t", help="Run command from text (skip mic)")
    parser.add_argument("--seconds", type=float, default=4.0, help="Mic record length")
    parser.add_argument("--dry-run", action="store_true", help="Print hyprctl only")
    parser.add_argument("--no-ollama", action="store_true", help="Disable Ollama fallback")
    parser.add_argument("--whisper-model", default="base", help="Faster-Whisper model size")
    parser.add_argument("--audio", help="Transcribe existing wav/mp3 instead of recording")
    args = parser.parse_args(argv)

    text = (args.text or "").strip()
    if not text:
        with tempfile.TemporaryDirectory(prefix="endeavouros-ai-") as tmp:
            audio = Path(args.audio) if args.audio else Path(tmp) / "utterance.wav"
            if not args.audio:
                record_audio(args.seconds, audio)
            transcribed = transcribe_faster_whisper(audio, args.whisper_model)
            if not transcribed:
                print(
                    "[ai] No transcript. Pass --text 'workspace 2' or install faster-whisper.",
                    file=sys.stderr,
                )
                return 1
            text = transcribed
            print(f"[ai] heard: {text}")

    action = resolve_action(text, use_ollama=not args.no_ollama)
    if not action:
        print(f"[ai] could not parse command: {text!r}", file=sys.stderr)
        return 2

    return run_hyprctl(action, dry_run=args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
