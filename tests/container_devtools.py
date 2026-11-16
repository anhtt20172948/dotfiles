"""Exercise the real setup entry point with a local upstream and isolated user home."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / ".local/bin/container-devtools"
URL = "https://github.com/anhtt20172948/dotfiles"


class ContainerSetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "container home"
        self.home.mkdir()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.upstream = self.base / "upstream"
        self.upstream.mkdir()
        self.git = shutil.which("git")
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=str(self.bin) + ":" + os.environ["PATH"],
                        UPSTREAM=str(self.upstream), REAL_GIT=self.git)
        self.write_bin("docker", '''#!/usr/bin/env python3
import os, subprocess, sys
args = sys.argv[1:]
if args[0] == 'ps': print('abc test (debian)')
elif args[0] == 'inspect': print('true' if 'Running' in args[2] else 'abc')
elif args[0] == 'exec':
    args = args[1:]
    if args[0] == '-i': args = args[1:]
    sys.exit(subprocess.call(args[1:]))
else: sys.exit(2)
''')
        self.write_bin("git", '''#!/usr/bin/env python3
import os, sys
args = [os.environ['UPSTREAM'] if a == 'https://github.com/anhtt20172948/dotfiles' else a for a in sys.argv[1:]]
os.execv(os.environ['REAL_GIT'], ['git'] + args)
''')
        self.git_run("init", "-b", "main", str(self.upstream))
        (self.upstream / "install.sh").write_text(
            '#!/usr/bin/env bash\nset -eu\nln -sf "$HOME/dotfiles/config" "$HOME/linked"\n')
        (self.upstream / "config").write_text("original\n")
        self.commit("initial")

    def write_bin(self, name, text):
        path = self.bin / name
        path.write_text(text)
        path.chmod(0o755)

    def git_run(self, *args):
        return subprocess.run([self.git, "-C", str(self.upstream), *args],
                              check=True, capture_output=True, text=True,
                              env=dict(self.env, GIT_AUTHOR_NAME="Test", GIT_AUTHOR_EMAIL="test@example.org",
                                       GIT_COMMITTER_NAME="Test", GIT_COMMITTER_EMAIL="test@example.org"))

    def commit(self, message):
        self.git_run("add", ".")
        self.git_run("commit", "-m", message)

    def run_setup(self, items, success=True, input=""):
        result = subprocess.run([str(SCRIPT), "--container", "test", "--tools", items],
                                env=self.env, capture_output=True, text=True, input=input, timeout=30)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def test_path_missing_file_rerun_and_fresh_shell(self):
        self.run_setup("path")
        self.run_setup("path")
        rc = self.home / ".bashrc"
        self.assertEqual(rc.read_text().count('export PATH="$HOME/.local/bin:$PATH"'), 1)
        binary = self.home / ".local/bin/rg"
        binary.parent.mkdir(parents=True)
        binary.write_text("#!/bin/sh\nexit 0\n")
        binary.chmod(0o755)
        shell = subprocess.run(["bash", "-ic", "command -v rg"], env=self.env,
                               capture_output=True, text=True)
        self.assertEqual(shell.stdout.strip(), str(binary))

    def test_path_preserves_unterminated_rc(self):
        rc = self.home / ".bashrc"
        rc.write_text("# custom config")
        self.run_setup("path")
        self.assertTrue(rc.read_text().startswith("# custom config\n"))

    def test_dotfiles_updates_and_preserves_user_changes(self):
        self.run_setup("dotfiles,path")
        checkout = self.home / "dotfiles"
        self.assertTrue((self.home / "linked").is_symlink())
        (checkout / "config").write_text("user edit\n")
        (checkout / "private").write_text("untracked\n")
        (self.upstream / "new").write_text("new upstream\n")
        self.commit("update")
        self.run_setup("dotfiles")
        self.assertEqual((checkout / "config").read_text(), "user edit\n")
        self.assertEqual((checkout / "private").read_text(), "untracked\n")
        self.assertTrue((checkout / "new").is_file())
        self.run_setup("dotfiles")
        self.assertEqual((self.home / "linked").read_text(), "user edit\n")

    def test_conflicting_changes_are_untouched_and_path_still_runs(self):
        self.run_setup("dotfiles")
        config = self.home / "dotfiles/config"
        config.write_text("user edit\n")
        (self.upstream / "config").write_text("conflict\n")
        self.commit("conflict")
        output = self.run_setup("dotfiles,path", success=False)
        self.assertIn("dotfiles: FAILED", output)
        self.assertIn("path:", output)
        self.assertEqual(config.read_text(), "user edit\n")

    def test_missing_requirements_keeps_download_and_reports_skip(self):
        self.write_bin("python3", "#!/bin/sh\nexit 1\n")
        # Keep engine/git stubs runnable even when the container python probe fails.
        for name in ("docker", "git"):
            path = self.bin / name
            path.write_text(path.read_text().replace("#!/usr/bin/env python3", "#!/usr/bin/python3"))
        output = self.run_setup("dotfiles,path")
        self.assertIn("downloaded", output)
        self.assertIn("Python 3.11+", output)
        self.assertFalse((self.home / "linked").exists())
        self.assertTrue((self.home / "dotfiles/install.sh").is_file())

    def test_foreign_checkout_is_preserved(self):
        checkout = self.home / "dotfiles"
        checkout.mkdir()
        (checkout / "mine").write_text("keep")
        self.run_setup("dotfiles", success=False)
        self.assertEqual((checkout / "mine").read_text(), "keep")

    def test_checkout_hooks_and_filters_do_not_execute_on_host(self):
        self.run_setup("dotfiles")
        checkout = self.home / "dotfiles"
        marker = self.base / "executed"
        subprocess.run([self.git, "-C", str(checkout), "config", "filter.unsafe.smudge",
                        "touch " + str(marker)], check=True)
        hook = checkout / ".git/hooks/post-merge"
        hook.write_text("#!/bin/sh\ntouch " + str(marker) + "\n")
        hook.chmod(0o755)
        (self.upstream / ".gitattributes").write_text("*.filtered filter=unsafe\n")
        (self.upstream / "new.filtered").write_text("new\n")
        self.commit("filtered upstream")
        self.run_setup("dotfiles")
        self.assertFalse(marker.exists())
        config = subprocess.run([self.git, "-C", str(checkout), "config", "filter.unsafe.smudge"],
                                capture_output=True, text=True, check=True)
        self.assertIn(str(marker), config.stdout)

    def test_symlink_checkout_is_untouched(self):
        target = self.base / "elsewhere"
        target.mkdir()
        (self.home / "dotfiles").symlink_to(target)
        self.run_setup("dotfiles", success=False)
        self.assertTrue((self.home / "dotfiles").is_symlink())
        self.assertEqual(list(target.iterdir()), [])

    def test_numbered_menu_defaults_include_setup(self):
        # Limit PATH to real system tools plus our engine and Git stubs.
        for name in ("bash", "sh", "python3", "uname", "mktemp", "rm", "mkdir", "tar",
                     "cat", "grep", "touch", "readlink", "cp", "mv", "find", "chmod", "ln"):
            (self.bin / name).symlink_to(shutil.which(name))
        self.env["PATH"] = str(self.bin)
        result = subprocess.run([str(SCRIPT), "--container", "test"], env=self.env,
                                capture_output=True, text=True, input="1 2\n", timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("path [default]", result.stdout)
        self.assertIn("dotfiles [default]", result.stdout)
        self.assertTrue((self.home / ".bashrc").is_file())
        self.assertTrue((self.home / "linked").is_symlink())

    def test_invalid_selection(self):
        self.assertIn("Unknown tool", self.run_setup("bogus", success=False))


if __name__ == "__main__":
    unittest.main()
