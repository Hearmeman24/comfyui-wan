#!/usr/bin/env python3
"""Self-check: the validate_models shim resolves the runtime pin FRESH.

pins.json pins `runtime_ref: "stable"`, a BRANCH. The shim keeps one cached
clone of comfyui-runtime at ~/.cache/comfyui-runtime-validator. It used to
fetch only when the ref did not resolve locally, so once that cache held a
local `stable` branch it never refreshed: on 2026-11-26 the cache sat at
0ea1f91 while origin's `stable` was 1e97ec1, and the provisioner tests failed
locally while CI (fresh clone every run) was green.

Every case here runs against a throwaway bare "origin" and a throwaway cache,
never the network and never the real ~/.cache clone.

Run: python3 tools/test_validate_models_shim.py
Stdlib only, no pytest.
"""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import validate_models as shim  # noqa: E402

# Isolate every git call (ours and the shim's) from the user's git config.
GIT_ENV = {
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
    "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid",
}


def git(cwd: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(cwd), *args], check=True,
                          capture_output=True, text=True).stdout.strip()


class ShimResolveRuntime(unittest.TestCase):
    def setUp(self):
        env = mock.patch.dict(os.environ, GIT_ENV)
        env.start()
        self.addCleanup(env.stop)
        os.environ.pop("COMFYUI_RUNTIME_DIR", None)

        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.origin = self.tmp / "origin.git"
        self.work = self.tmp / "work"
        self.cache = self.tmp / "cache"

        subprocess.run(["git", "init", "-q", "--bare", "-b", "main",
                        str(self.origin)], check=True)
        subprocess.run(["git", "clone", "-q", str(self.origin),
                        str(self.work)], check=True, capture_output=True)
        git(self.work, "checkout", "-q", "-b", "main")
        self.a = self.commit("A")
        git(self.work, "push", "-q", "origin", "main", "main:stable")

        for name, value in (("CACHE", self.cache),
                            ("RUNTIME_URL", str(self.origin))):
            p = mock.patch.object(shim, name, value)
            p.start()
            self.addCleanup(p.stop)

    def commit(self, label: str) -> str:
        (self.work / "marker").write_text(label)
        git(self.work, "add", "marker")
        git(self.work, "commit", "-q", "-m", label)
        return git(self.work, "rev-parse", "HEAD")

    def advance_stable(self) -> str:
        b = self.commit("B")
        git(self.work, "push", "-q", "origin", "main", "main:stable")
        return b

    def seed_cache_with_local_stable(self):
        """The 2026-11-26 cache: a clone holding a LOCAL `stable` branch."""
        subprocess.run(["git", "clone", "-q", str(self.origin),
                        str(self.cache)], check=True, capture_output=True)
        git(self.cache, "checkout", "-q", "-b", "stable", "origin/stable")

    def head(self) -> str:
        return git(self.cache, "rev-parse", "HEAD")

    def test_stale_local_branch_is_refreshed(self):
        self.seed_cache_with_local_stable()
        b = self.advance_stable()
        self.assertEqual(shim.resolve_runtime("stable"), self.cache)
        self.assertEqual(self.head(), b,
                         "cache served its stale local `stable` instead of "
                         "origin's")

    def test_first_run_clones_and_tracks_branch(self):
        self.assertEqual(shim.resolve_runtime("stable"), self.cache)
        self.assertEqual(self.head(), self.a)
        b = self.advance_stable()
        shim.resolve_runtime("stable")
        self.assertEqual(self.head(), b)

    def test_branch_fetch_failure_is_fatal_not_stale(self):
        self.seed_cache_with_local_stable()
        git(self.cache, "remote", "set-url", "origin",
            str(self.tmp / "gone.git"))
        with mock.patch.object(shim, "REPO", self.pins('"stable"')):
            with self.assertRaises(SystemExit) as cm:
                shim.runtime_dir()
        self.assertIn("FATAL", str(cm.exception))

    def test_full_sha_present_stays_offline(self):
        self.seed_cache_with_local_stable()
        self.advance_stable()
        git(self.cache, "remote", "set-url", "origin",
            str(self.tmp / "gone.git"))
        shim.resolve_runtime(self.a)
        self.assertEqual(self.head(), self.a)

    def test_full_sha_absent_is_fetched(self):
        self.seed_cache_with_local_stable()
        b = self.advance_stable()
        shim.resolve_runtime(b)
        self.assertEqual(self.head(), b)

    def test_override_dir_is_used_as_is(self):
        local = self.tmp / "local-runtime"
        with mock.patch.dict(os.environ, {"COMFYUI_RUNTIME_DIR": str(local)}):
            self.assertEqual(shim.runtime_dir(), local)
        self.assertFalse(self.cache.exists(), "override must not touch git")

    def pins(self, ref_json: str) -> Path:
        repo = self.tmp / "repo"
        repo.mkdir(exist_ok=True)
        (repo / "pins.json").write_text('{"runtime_ref": %s}' % ref_json)
        return repo


if __name__ == "__main__":
    unittest.main(verbosity=2)
