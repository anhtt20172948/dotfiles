"""Run the real helper entry points without network, mounts, or desktop apps."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
REAL_RSYNC = shutil.which("rsync")

# External effects are recorded as argv arrays. SSH never reaches the network.
STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["CALLS"], "a") as log:
    log.write(json.dumps([name] + args) + "\n")
if name == "uname":
    print(os.environ["PLATFORM"])
elif name == "ssh":
    if "-F" in args and not pathlib.Path(args[args.index("-F") + 1]).is_file():
        sys.exit(1)
    if os.environ.get("TRANSPORT_PROBE"):
        sys.exit(1)
    if os.environ.get("MISSING"):
        sys.exit(1)
    if args[-1].startswith("du "):
        print("4K")
    elif args[-1].startswith("test -d "):
        print(os.environ.get("IS_DIR", "0"))
elif name == "sshfs":
    if os.environ.get("MOUNT_FAIL"):
        sys.exit(1)
    target = args[args.index(next(a for a in args if a.endswith(":/"))) + 1]
    local = pathlib.Path(target + os.environ["REMOTE_PATH"])
    local.parent.mkdir(parents=True, exist_ok=True)
    if os.environ.get("IS_DIR") == "1":
        local.mkdir(exist_ok=True)
    else:
        local.write_text("remote content")
elif name == "mountpoint":
    sys.exit(0 if os.environ.get("MOUNTED") else 1)
elif name == "mount":
    if os.environ.get("MOUNTED"):
        print("remote:/ on " + os.path.realpath(os.environ["MOUNT_POINT"]) + " (macfuse, nodev)")
elif name in ("fusermount3", "fusermount"):
    sys.exit(0 if os.environ.get("FUSE_SUCCESS", "1") == "1" else 1)
elif name == "realpath":
    sys.exit("GNU realpath must not be needed")
elif name == "rsync":
    if "--version" in args:
        sys.exit(0 if os.environ.get("PROGRESS2", "1") == "1" else 1)
    sys.exit(int(os.environ.get("TRANSFER_FAIL", "0")))
elif name == "tmux":
    if args[0] == "display-message":
        print(os.environ["WINDOW_NAME"])
    elif args[0] == "display-popup":
        sys.exit(subprocess.call(["/bin/sh", "-c", args[-1]]))
'''


class HelperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="remote-helpers-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        for name in ("ssh", "sshfs", "rsync", "uname", "mountpoint", "mount",
                     "open", "xdg-open", "kitty", "libreoffice", "sleep",
                     "fusermount3", "fusermount", "umount", "realpath", "tmux"):
            path = self.bin / name
            path.write_text(STUB)
            path.chmod(0o755)
        self.home = self.base / "home"
        self.home.mkdir()
        self.config = self.base / "ssh configs" / "work 'quoted' config"
        self.config.parent.mkdir()
        self.alias = "review" + self.base.name
        self.config.write_text(
            "Host * !skip ?pattern\nHost " + self.alias + " " + self.alias
            + " # deduplicate\n  HostName example.invalid\n")
        self.calls = self.base / "calls.jsonl"
        self.calls.touch()
        bash_env = self.base / "bash-env"
        bash_env.write_text("enable -n mapfile 2>/dev/null || true\n")
        self.mount = Path("/tmp/mnt_show_" + self.alias)
        self.addCleanup(lambda: shutil.rmtree(self.mount, ignore_errors=True))
        self.env = dict(os.environ, PATH=str(self.bin) + ":" + os.environ["PATH"],
                        HOME=str(self.home), SSH_CONFIG=str(self.config),
                        CALLS=str(self.calls), PLATFORM="Linux",
                        REMOTE_PATH="/folder with spaces/a 'quoted' $(literal).txt",
                        MOUNT_POINT=str(self.mount), TMPDIR=str(self.base),
                        BASH_ENV=str(bash_env))
        self.env.pop("REMOTE_HOSTS", None)

    def records(self, name):
        return [r[1:] for r in map(json.loads, self.calls.read_text().splitlines())
                if r[0] == name]

    def run_helper(self, name, *args, success=True):
        result = subprocess.run([str(ROOT / ".local/bin" / name), *args],
                                env=self.env, cwd=self.base, input="", text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=10)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result.stdout

    def assert_config(self, args):
        self.assertIn("-F", args, args)
        self.assertEqual(args[args.index("-F") + 1], str(self.config))

    def wait_for(self, name):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if self.records(name):
                return self.records(name)
            time.sleep(0.01)
        self.fail("background command never ran: " + name)

    def test_download_config_discovery_and_every_connection(self):
        for is_dir in ("0", "1"):
            with self.subTest(is_dir=is_dir):
                self.calls.write_text("")
                self.env["IS_DIR"] = is_dir
                self.env["PROGRESS2"] = "0"
                self.run_helper("download", self.env["REMOTE_PATH"],
                                "missing parent/destination with spaces")
                connections = self.records("ssh")
                self.assertEqual(len(connections), 3)
                for args in connections:
                    self.assert_config(args)
                    self.assertIn(self.alias, args)
                # Execute the probe string through a POSIX shell, as SSH does.
                probe = connections[0][-1]
                # The remote path's shell metacharacters must remain data.
                shell = subprocess.run(["/bin/sh", "-c", probe.replace("test -e ", "printf '%s' ", 1)],
                                       capture_output=True, text=True)
                self.assertEqual(shell.stdout, self.env["REMOTE_PATH"])
                transfer = self.records("rsync")[-1]
                self.assertIn("--progress", transfer)
                self.assertEqual(transfer[-2], self.alias + ":" + self.env["REMOTE_PATH"]
                                 + ("/" if is_dir == "1" else ""))
                self.assertEqual(transfer[-1], str(self.base / "missing parent/destination with spaces")
                                 + ("/" if is_dir == "1" else ""))
                self.assertTrue((self.base / "missing parent").is_dir())
                if REAL_RSYNC:
                    # Real rsync parses -e itself; shell quoting alone is insufficient.
                    transport = transfer[transfer.index("-e") + 1]
                    before = len(connections)
                    subprocess.run([REAL_RSYNC, "-n", "-e", transport,
                                    self.alias + ":/demo", str(self.base / "out")],
                                   env=dict(self.env, TRANSPORT_PROBE="1"),
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=5)
                    actual = self.records("ssh")[before:]
                    self.assertEqual(len(actual), 1)
                    self.assert_config(actual[0])
                else:
                    self.fail("rsync required to check transport quoting")

    def test_show_platform_mount_open_and_unmount(self):
        for platform in ("Linux", "Darwin"):
            for is_dir in ("0", "1"):
                with self.subTest(platform=platform, is_dir=is_dir):
                    shutil.rmtree(self.mount, ignore_errors=True)
                    self.calls.write_text("")
                    self.env.update(PLATFORM=platform, IS_DIR=is_dir, FUSE_SUCCESS="0")
                    self.run_helper("show", self.env["REMOTE_PATH"])
                    self.assertEqual(len(self.records("ssh")), 1)
                    self.assert_config(self.records("ssh")[0])
                    self.assert_config(self.records("sshfs")[0])
                    opener = "open" if platform == "Darwin" else "xdg-open"
                    self.assertEqual(self.wait_for(opener), [[str(self.mount) + self.env["REMOTE_PATH"]]])
                    self.assertEqual(self.wait_for("umount"), [[str(self.mount)]])
                    if platform == "Darwin":
                        self.assertTrue(self.records("mount"))
                        self.assertFalse(self.records("mountpoint"))
                        self.assertFalse(self.records("fusermount3"))
                    else:
                        self.assertTrue(self.records("mountpoint"))
                        self.assertEqual(self.records("fusermount3"), [["-u", str(self.mount)]])

    def test_show_reuses_darwin_mount_and_opens_code_with_default_app(self):
        self.env.update(PLATFORM="Darwin", MOUNTED="1", REMOTE_PATH="/sample.py")
        self.mount.mkdir()
        (self.mount / "sample.py").write_text("print('hello')")
        self.run_helper("show", "/sample.py")
        self.assertEqual(self.wait_for("open"), [[str(self.mount / "sample.py")]])
        self.wait_for("umount")
        self.assertFalse(self.records("sshfs"))
        self.assertFalse(self.records("kitty"))

    def test_failures_do_not_open_or_transfer(self):
        self.env["MISSING"] = "1"
        for name in ("show", "download"):
            self.run_helper(name, "/missing", success=False)
        self.assertFalse(self.records("sshfs"))
        self.assertFalse(self.records("rsync"))
        self.env.pop("MISSING")
        self.env["TRANSFER_FAIL"] = "1"
        self.assertIn("Download failed", self.run_helper("download", "/demo", success=False))
        self.env["MOUNT_FAIL"] = "1"
        self.assertIn("Failed to mount", self.run_helper("show", "/demo", success=False))
        self.assertFalse(self.records("open"))
        self.assertFalse(self.records("xdg-open"))

    def test_remote_hosts_override_without_a_config(self):
        self.env.pop("SSH_CONFIG")
        self.env["REMOTE_HOSTS"] = self.alias
        self.run_helper("download", "/demo")
        self.run_helper("show", self.env["REMOTE_PATH"])
        self.wait_for("fusermount3")
        for args in self.records("ssh"):
            self.assertIn(self.alias, args)
            self.assertNotIn("-F", args)

    def test_rename_popup_keeps_window_name_as_data(self):
        binding = re.search(r"bind , run-shell '(.*?)\n'", (ROOT / ".config/tmux/keymaps.conf").read_text(), re.S)[1]
        scripts = self.home / ".config/tmux/scripts"
        scripts.mkdir(parents=True)
        (scripts / "rename-window.sh").symlink_to(ROOT / ".config/tmux/scripts/rename-window.sh")
        marker = self.base / "executed"
        for window_name in ("$(touch " + str(marker) + ")", 'both \'single\' and "double" quotes'):
            with self.subTest(window_name=window_name):
                marker.unlink(missing_ok=True)
                result = subprocess.run(["/bin/sh", "-c", binding],
                                        env=dict(self.env, WINDOW_NAME=window_name),
                                        input="safe name\n", text=True, capture_output=True, timeout=5)
                self.assertFalse(marker.exists(), "window name executed as shell code")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(window_name, result.stdout)
                self.assertEqual(self.records("tmux")[-1], ["rename-window", "--", "safe name"])


if __name__ == "__main__":
    unittest.main()
