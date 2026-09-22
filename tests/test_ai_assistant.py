#!/usr/bin/env python3
"""
Unit-тесты AI-ассистента EndeavourOS против scripts/ai_assistant.py.

Контракт реального модуля:
  - parse_simple_command(phrase) → list argv для hyprctl БЕЗ бинарника
    (напр. ["dispatch", "workspace", "2"]) или None
  - resolve_action(text, use_ollama) — парсер + опциональный Ollama
  - run_hyprctl(args, dry_run=False) — subprocess.run(["hyprctl", *args])
"""
from __future__ import annotations

import importlib.util
import subprocess
import sys
import unittest
from pathlib import Path
from typing import Any, Callable, List, Optional, Sequence
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
AI_PATH = ROOT / "scripts" / "ai_assistant.py"


def _load_real_module():
    if not AI_PATH.is_file():
        _load_real_module.load_error = FileNotFoundError(AI_PATH)  # type: ignore[attr-defined]
        return None
    spec = importlib.util.spec_from_file_location("ai_assistant", AI_PATH)
    if spec is None or spec.loader is None:
        _load_real_module.load_error = RuntimeError("spec_from_file_location failed")  # type: ignore[attr-defined]
        return None
    mod = importlib.util.module_from_spec(spec)
    sys.modules["ai_assistant"] = mod
    try:
        spec.loader.exec_module(mod)
    except Exception as exc:  # noqa: BLE001 — сообщаем в тесте
        _load_real_module.load_error = exc  # type: ignore[attr-defined]
        return None
    _load_real_module.load_error = None  # type: ignore[attr-defined]
    return mod


def resolve_parse_fn(mod) -> Callable[[str], Any]:
    if mod is None:
        raise unittest.SkipTest("scripts/ai_assistant.py не загрузился")
    for name in (
        "parse_simple_command",
        "parse_command",
        "parse_phrase",
        "phrase_to_hyprctl",
        "to_hyprctl",
        "resolve_action",
    ):
        fn = getattr(mod, name, None)
        if not callable(fn):
            continue
        if name == "resolve_action":
            return lambda phrase, _fn=fn: _fn(phrase, use_ollama=False)
        return fn
    raise unittest.SkipTest(
        "в ai_assistant.py нет parse_simple_command / parse_command / resolve_action"
    )


def normalize_argv(result: Any) -> Optional[List[str]]:
    """Привести результат парсера к list[str] argv с hyprctl впереди."""
    if result is None:
        return None
    if isinstance(result, str):
        parts = result.split()
    elif isinstance(result, Sequence) and not isinstance(result, (str, bytes)):
        parts = [str(x) for x in result]
    elif isinstance(result, dict):
        if "argv" in result:
            parts = [str(x) for x in result["argv"]]
        else:
            dispatch = result.get("dispatch") or result.get("command")
            args = result.get("args") or result.get("arguments") or []
            if dispatch == "reload" or result.get("action") == "reload":
                parts = ["reload"]
            elif isinstance(dispatch, list):
                parts = [str(x) for x in dispatch]
                if parts and parts[0] != "dispatch":
                    parts = ["dispatch", *parts]
            elif dispatch:
                parts = ["dispatch", str(dispatch), *[str(a) for a in args]]
            else:
                return None
    else:
        return None

    if not parts:
        return None
    if parts[0] != "hyprctl":
        parts = ["hyprctl", *parts]
    return parts


class TestAiAssistantModule(unittest.TestCase):
    def test_module_loads(self):
        mod = _load_real_module()
        err = getattr(_load_real_module, "load_error", None)
        self.assertIsNotNone(mod, f"не удалось загрузить {AI_PATH}: {err}")
        self.assertTrue(hasattr(mod, "parse_simple_command"))
        self.assertTrue(hasattr(mod, "run_hyprctl"))


class TestAiAssistantParse(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = _load_real_module()
        if cls.mod is None:
            err = getattr(_load_real_module, "load_error", None)
            raise unittest.SkipTest(f"ai_assistant.py не загрузился: {err}")
        cls._parse_fn = staticmethod(resolve_parse_fn(cls.mod))
        print("INFO: загружен scripts/ai_assistant.py", file=sys.stderr)

    def _argv(self, phrase: str) -> Optional[List[str]]:
        return normalize_argv(self._parse_fn(phrase))

    def test_workspace_english(self):
        argv = self._argv("workspace 2")
        self.assertIsNotNone(argv)
        joined = " ".join(argv)
        self.assertIn("hyprctl", joined)
        self.assertIn("dispatch", joined)
        self.assertIn("workspace", joined)
        self.assertIn("2", joined)

    def test_workspace_russian(self):
        argv = self._argv("рабочий стол 3")
        self.assertIsNotNone(argv)
        joined = " ".join(argv)
        self.assertIn("workspace", joined)
        self.assertIn("3", joined)

    def test_killactive_russian(self):
        argv = self._argv("закрой окно")
        self.assertIsNotNone(argv)
        joined = " ".join(argv)
        self.assertIn("killactive", joined)
        self.assertIn("dispatch", joined)

    def test_killactive_english(self):
        argv = self._argv("close window")
        self.assertIsNotNone(argv)
        self.assertIn("killactive", " ".join(argv))

    def test_unknown_returns_empty(self):
        argv = self._argv("свари кофе пожалуйста")
        self.assertTrue(argv is None or argv == [] or argv == [""])


class TestAiAssistantSubprocess(unittest.TestCase):
    """Мок subprocess — без реального hyprland."""

    @classmethod
    def setUpClass(cls):
        cls.mod = _load_real_module()
        if cls.mod is None:
            err = getattr(_load_real_module, "load_error", None)
            raise unittest.SkipTest(f"ai_assistant.py не загрузился: {err}")

    def test_subprocess_called_for_workspace(self):
        run_hyprctl = getattr(self.mod, "run_hyprctl", None)
        self.assertTrue(callable(run_hyprctl))

        with mock.patch("subprocess.run") as mocked:
            mocked.return_value = mock.Mock(returncode=0, stdout="", stderr="")
            # run_hyprctl принимает args без "hyprctl"
            rc = run_hyprctl(["dispatch", "workspace", "2"], dry_run=False)
            self.assertEqual(rc, 0)
            self.assertTrue(mocked.called, "subprocess.run должен быть вызван")
            args, _kwargs = mocked.call_args
            argv = list(args[0]) if args else []
            joined = " ".join(str(a) for a in argv)
            self.assertIn("hyprctl", joined)
            self.assertIn("workspace", joined)
            self.assertIn("2", joined)

    def test_subprocess_called_for_kill(self):
        parse = getattr(self.mod, "parse_simple_command")
        run_hyprctl = getattr(self.mod, "run_hyprctl")
        action = parse("закрой окно")
        self.assertIsNotNone(action)

        with mock.patch("subprocess.run") as mocked:
            mocked.return_value = mock.Mock(returncode=0, stdout="", stderr="")
            run_hyprctl(action, dry_run=False)
            self.assertTrue(mocked.called)
            joined = " ".join(str(a) for a in mocked.call_args[0][0])
            self.assertIn("killactive", joined)

    def test_dry_run_skips_subprocess(self):
        run_hyprctl = getattr(self.mod, "run_hyprctl")
        with mock.patch("subprocess.run") as mocked:
            rc = run_hyprctl(["dispatch", "workspace", "1"], dry_run=True)
            self.assertEqual(rc, 0)
            mocked.assert_not_called()


class TestContractDocumentation(unittest.TestCase):
    def test_expected_path(self):
        self.assertEqual(AI_PATH, ROOT / "scripts" / "ai_assistant.py")
        self.assertTrue(AI_PATH.is_file(), f"ожидается файл {AI_PATH}")

    def test_parse_covers_plan_phrases(self):
        mod = _load_real_module()
        self.assertIsNotNone(mod)
        parse = mod.parse_simple_command
        self.assertEqual(parse("workspace 2"), ["dispatch", "workspace", "2"])
        self.assertEqual(parse("закрой окно"), ["dispatch", "killactive"])


if __name__ == "__main__":
    result = unittest.main(verbosity=2, exit=False)
    sys.exit(0 if result.result.wasSuccessful() else 1)
