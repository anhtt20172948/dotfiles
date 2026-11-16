"""Exercise the real setup entry point with a local upstream and isolated user home."""
import hashlib
import io
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import unittest
import zipfile

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
        self.script = SCRIPT
        self.upstream = self.base / "upstream"
        self.upstream.mkdir()
        self.git = shutil.which("git")
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=str(self.bin) + ":" + os.environ["PATH"],
                        UPSTREAM=str(self.upstream), REAL_GIT=self.git,
                        CONTAINER_ARCH="x86_64")
        self.write_bin("uname", '''#!/bin/sh
case $1 in
    -m) printf '%s\\n' "$CONTAINER_ARCH" ;;
    -s) printf 'Linux\\n' ;;
    *) exit 2 ;;
esac
''')
        self.write_bin("docker", '''#!/usr/bin/env python3
import os, subprocess, sys
args = sys.argv[1:]
if args[0] == 'ps':
    assert args[-1] == '{{.Names}} ({{.Image}}) {{.Status}}', args
    print('test (debian) Up 5 minutes')
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
        result = subprocess.run([str(self.script), "--container", "test", "--tools", items],
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
        self.write_bin("python3", "#!/bin/sh\necho 'ModuleNotFoundError: No module named tomllib' >&2\nexit 1\n")
        # Keep engine/git stubs runnable even when the container python probe fails.
        for name in ("docker", "git"):
            path = self.bin / name
            path.write_text(path.read_text().replace("#!/usr/bin/env python3", "#!/usr/bin/python3"))
        output = self.run_setup("dotfiles,path")
        self.assertIn("downloaded", output)
        self.assertIn("Python 3.11+", output)
        self.assertNotIn("ModuleNotFoundError", output)
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

    def isolate_path(self):
        # Exclude host menu tools and installed binaries from the fake container.
        for name in ("bash", "sh", "python3", "mktemp", "rm", "mkdir", "tar", "gzip",
                     "cat", "grep", "touch", "readlink", "cp", "mv", "find", "chmod", "ln"):
            (self.bin / name).symlink_to(shutil.which(name))
        self.env = dict(self.env, PATH=str(self.bin))

    def test_fzf_container_picker_precedes_gum_and_resolves_name(self):
        self.isolate_path()
        self.env = dict(self.env, XDG_CONFIG_HOME=str(ROOT / ".config"))
        self.write_bin("gum", "#!/bin/sh\nexit 99\n")
        self.write_bin("fzf", """#!/bin/sh
printf '%s\\n' "$@" > "$HOME/fzf-args"
cat > "$HOME/fzf-rows"
printf 'test (debian) Up 5 minutes\\n'
""")
        docker = self.bin / "docker"
        docker.write_text(docker.read_text().replace(
            "elif args[0] == 'inspect': print('true' if 'Running' in args[2] else 'abc')",
            "elif args[0] == 'inspect':\n"
            "    assert args[-1] == ('abc' if 'Running' in args[2] else 'test'), args\n"
            "    print('true' if 'Running' in args[2] else 'abc')"))
        result = subprocess.run([str(SCRIPT), "--tools", "path"], env=self.env,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.home / "fzf-rows").read_text(), "test (debian) Up 5 minutes\n")
        args = (self.home / "fzf-args").read_text()
        self.assertIn("--height=100%", args)
        self.assertIn("--reverse", args)
        self.assertIn("--color=16,bg:-1", args)
        self.assertTrue((self.home / ".bashrc").is_file())

    def test_container_picker_fallbacks(self):
        for picker in ("numbered", "gum"):
            with self.subTest(picker=picker):
                if picker == "numbered":
                    self.isolate_path()
                    bash_env = self.base / "bash-env"
                    bash_env.write_text("enable -n mapfile 2>/dev/null || true\n")
                    self.env = dict(self.env, BASH_ENV=str(bash_env))
                else:
                    self.write_bin("gum", "#!/bin/sh\ncat\n")
                result = subprocess.run([str(SCRIPT), "--tools", "path"], env=self.env,
                                        capture_output=True, text=True, input="1\n", timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("path: configured", result.stdout)

    def test_numbered_menu_defaults_include_setup(self):
        self.isolate_path()
        result = subprocess.run([str(SCRIPT), "--container", "test"], env=self.env,
                                capture_output=True, text=True, input="1 2\n", timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("path [default]", result.stdout)
        self.assertIn("dotfiles [default]", result.stdout)
        self.assertIn("clangd", result.stdout)
        self.assertIn("clang-tidy", result.stdout)
        self.assertNotIn("clangd [default]", result.stdout)
        self.assertNotIn("clang-tidy [default]", result.stdout)
        self.assertTrue((self.home / ".bashrc").is_file())
        self.assertTrue((self.home / "linked").is_symlink())

    def test_architecture_names_select_matching_release_assets(self):
        self.write_bin("curl", '''#!/usr/bin/env python3
import io, os, pathlib, sys, tarfile
args = sys.argv[1:]
pathlib.Path(os.environ['FETCH_LOG']).write_text(args[-1])
with tarfile.open(args[args.index('-o') + 1], 'w:gz') as archive:
    content = b'#!/bin/sh\\nprintf "fzf test\\n"\\n'
    info = tarfile.TarInfo('fzf')
    info.mode = 0o755
    info.size = len(content)
    archive.addfile(info, io.BytesIO(content))
''')
        self.isolate_path()
        fetch_log = self.base / "fetch-url"
        for arch, asset_arch in (("x86_64", "amd64"), ("amd64", "amd64"),
                                 ("aarch64", "arm64"), ("arm64", "arm64")):
            with self.subTest(arch=arch):
                self.env = dict(self.env, CONTAINER_ARCH=arch, FETCH_LOG=str(fetch_log))
                output = self.run_setup("fzf")
                self.assertIn("fzf: installed", output)
                self.assertTrue(fetch_log.read_text().endswith("linux_" + asset_arch + ".tar.gz"))
                (self.home / ".local/bin/fzf").unlink()

    def test_unsupported_architecture_is_rejected(self):
        self.env = dict(self.env, CONTAINER_ARCH="riscv64")
        self.assertIn("Unsupported container architecture: riscv64",
                      self.run_setup("path", success=False))

    def clang_fixtures(self, headers_present=True):
        self.isolate_path()
        # Exercise the Python fallback even on developer hosts that have unzip.
        for name in ("sha256sum", "shasum", "perl"):
            path = shutil.which(name)
            if path:
                (self.bin / name).symlink_to(path)
        self.write_bin("ldd", '#!/bin/sh\necho "${TEST_LIBC:-GNU libc}"\n')
        fixtures = self.base / "assets"
        fixtures.mkdir()
        binary = b'#!/bin/sh\nset -e\nexe=$(readlink -f "$0")\ntest -f "${exe%/bin/*}/lib/clang/22/include/stddef.h"\n'
        # The fake executable refuses to run without its adjacent resource tree.
        wheel = fixtures / "clangd.whl"
        with zipfile.ZipFile(wheel, "w") as z:
            z.writestr("clangd/data/bin/clangd", binary +
                       b'if [ "${TEST_LIBC:-}" = musl ]; then test -f "${exe%/clangd/data/bin/*}/clangd.libs/runtime.so"; fi\n')
            if headers_present:
                z.writestr("clangd/data/lib/clang/22/include/stddef.h", "// builtin\n")
            z.writestr("clangd.libs/runtime.so", "bundled runtime\n")
        tidy = fixtures / "clang-tidy"
        tidy.write_bytes(binary.replace(b"clang/22", b"clang/23"))
        headers = fixtures / "headers.tar.gz"
        with tarfile.open(headers, "w:gz") as t:
            content = b"// builtin\n"
            info = tarfile.TarInfo("lib/clang/23/include/stddef.h")
            info.size = len(content)
            t.addfile(info, io.BytesIO(content))
        hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in (wheel, tidy, headers)}
        source = SCRIPT.read_text()

        def fixture_hash(match):
            asset = match[1]
            key = ("clangd.whl" if asset.endswith(".whl") else
                   "headers.tar.gz" if asset.endswith(".tar.gz") else "clang-tidy")
            return asset + "|" + hashes[key]

        source = re.sub(r"(clang[^|\n]+)\|[a-f0-9]{64}", fixture_hash, source)
        self.script = self.base / "host/.local/bin/container-devtools"
        self.script.parent.mkdir(parents=True)
        shutil.copytree(ROOT / ".local/share/container-devtools",
                        self.base / "host/.local/share/container-devtools")
        self.script.write_text(source)
        self.script.chmod(0o755)
        self.env = dict(self.env, CLANG_FIXTURES=str(fixtures))
        self.write_bin("curl", '''#!/usr/bin/env python3
import os, pathlib, shutil, sys
args = sys.argv[1:]
url = args[-1]
with open(os.environ['HOME'] + '/fetch-log', 'a') as log: log.write(url + '\\n')
name = 'clangd.whl' if url.endswith('.whl') else 'headers.tar.gz' if url.endswith('.tar.gz') else 'clang-tidy'
shutil.copyfile(pathlib.Path(os.environ['CLANG_FIXTURES']) / name, args[args.index('-o') + 1])
''')

    def test_clang_tools_install_resources_for_both_architectures_and_libcs(self):
        self.clang_fixtures()
        for arch in ("x86_64", "aarch64"):
            for libc, platform in (("Debian GLIBC 2.41", "manylinux"), ("musl", "musllinux")):
                with self.subTest(arch=arch, libc=libc):
                    self.env = dict(self.env, CONTAINER_ARCH=arch, TEST_LIBC=libc)
                    output = self.run_setup("clangd,clang-tidy")
                    self.assertIn("clangd: installed", output)
                    self.assertIn("clang-tidy: installed", output)
                    for tool in ("clangd", "clang-tidy"):
                        subprocess.run([str(self.home / ".local/bin" / tool), "--version"],
                                       env=self.env, check=True)
                    log = (self.home / "fetch-log").read_text()
                    self.assertIn(platform, log)
                    self.assertIn(arch, log)
                    self.assertIn("skipped (already present)", self.run_setup("clangd,clang-tidy"))
                    shutil.rmtree(self.home / ".local")
                    (self.home / "fetch-log").unlink()

    def test_clang_checksum_failure_preserves_destination_and_continues(self):
        self.clang_fixtures()
        (self.base / "assets/clangd.whl").write_bytes(b"corrupt download")
        output = self.run_setup("clangd,path", success=False)
        self.assertIn("checksum", output.lower())
        self.assertIn("clangd: FAILED", output)
        self.assertIn("path: configured", output)
        self.assertFalse((self.home / ".local/bin/clangd").exists())

    def openmp_compiler(self):
        header = self.base / "compiler include/omp.h"
        header.parent.mkdir()
        header.write_text("/* container OpenMP runtime API */\n")
        self.env = dict(self.env, OPENMP_HEADER=str(header))
        self.write_bin("c++", '''#!/bin/sh
test "$#" = 1 || exit 2
case $1 in
    -print-file-name=include/omp.h) printf '%s\\n' "$OPENMP_HEADER" ;;
    -print-file-name=include) printf '%s\\n' "${OPENMP_HEADER%/omp.h}" ;;
    *) exit 2 ;;
esac
''')
        return header

    def test_both_clang_tools_supply_available_runtime_header_families(self):
        self.clang_fixtures()
        header = self.openmp_compiler()
        relatives = ("omp-tools.h", "ompt.h", "ompt-multiplex.h", "ompx.h", "openacc.h",
                     "ISO_Fortran_binding.h", "sanitizer/asan_interface.h",
                     "sanitizer/new_sdk_api.h", "xray/xray_interface.h",
                     "profile/instr_prof_interface.h", "orc_rt/c_api.h",
                     "fuzzer/FuzzedDataProvider.h")
        for relative in relatives:
            source = header.parent / relative
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("/* SDK " + relative + " */\n")
        self.run_setup("clangd,clang-tidy")
        for name, major in (("clangd", "22"), ("clang-tidy", "23")):
            executable = (self.home / ".local/bin" / name).resolve()
            include = executable.parent.parent / ("lib/clang/" + major + "/include")
            for relative in ("omp.h",) + relatives:
                with self.subTest(tool=name, header=relative):
                    self.assertTrue((include / relative).is_file(), relative)
                    self.assertEqual((include / relative).read_bytes(),
                                     (header.parent / relative).read_bytes())

    def test_clang_results_list_remaining_gaps_for_the_pinned_version(self):
        self.clang_fixtures()
        output = self.run_setup("clangd,clang-tidy")
        clangd = next(s for s in output.splitlines() if s.startswith("  clangd:"))
        tidy = next(s for s in output.splitlines() if s.startswith("  clang-tidy:"))
        self.assertIn("missing resource headers (LLVM 22.1.1)", clangd)
        self.assertIn("missing resource headers (LLVM 23.1.5)", tidy)
        for line in (clangd, tidy):
            self.assertIn("omp-tools.h", line)
            self.assertIn("fuzzer/FuzzedDataProvider.h", line)
            self.assertIn("orc_rt/c_api.h", line)
            self.assertNotIn("stddef.h", line)
        self.assertNotIn("sanitizer/safestack_interface.h", clangd)
        self.assertIn("sanitizer/safestack_interface.h", tidy)

    def test_clang_audit_accepts_a_complete_resource_directory(self):
        self.clang_fixtures()
        self.run_setup("clangd,clang-tidy")
        for name, version in (("clangd", "22.1.1"), ("clang-tidy", "23.1.5")):
            executable = (self.home / ".local/bin" / name).resolve()
            include = executable.parent.parent / ("lib/clang/" + version.split(".")[0] + "/include")
            manifest = ROOT / (".local/share/container-devtools/llvm-" + version + "-headers.txt")
            for relative in manifest.read_text().splitlines():
                if relative and not relative.startswith("#"):
                    header = include / relative
                    header.parent.mkdir(parents=True, exist_ok=True)
                    header.write_text("/* bundled runtime header */\n")
        output = self.run_setup("clangd,clang-tidy")
        self.assertIn("resource headers complete (LLVM 22.1.1 manifest)", output)
        self.assertIn("resource headers complete (LLVM 23.1.5 manifest)", output)
        self.assertNotIn("missing resource headers", output)

    def test_clang_missing_manifest_is_reported_and_other_items_continue(self):
        self.clang_fixtures()
        (self.base / "host/.local/share/container-devtools/llvm-22.1.1-headers.txt").unlink()
        output = self.run_setup("clangd,path", success=False)
        self.assertIn("Missing container-devtools runtime-header data", output)
        self.assertIn("clangd: FAILED", output)
        self.assertIn("path: configured", output)

    def test_clangd_supplies_container_openmp_header(self):
        self.clang_fixtures()
        header = self.openmp_compiler()
        self.env = dict(self.env, CONTAINER_ARCH="aarch64")
        self.run_setup("clangd")
        executable = (self.home / ".local/bin/clangd").resolve()
        supplied = executable.parent.parent / "lib/clang/22/include/omp.h"
        self.assertTrue(supplied.is_file(), "clangd cannot find the container OpenMP header")
        self.assertEqual(supplied.read_bytes(), header.read_bytes())
        self.assertEqual(header.read_text(), "/* container OpenMP runtime API */\n")

    def test_clangd_supplies_openmp_header_when_home_is_a_symlink(self):
        self.clang_fixtures()
        header = self.openmp_compiler()
        linked_home = self.base / "linked home"
        linked_home.symlink_to(self.home)
        self.env = dict(self.env, HOME=str(linked_home), CONTAINER_ARCH="aarch64")
        output = self.run_setup("clangd")
        self.assertNotIn("audit skipped", output)
        executable = (linked_home / ".local/bin/clangd").resolve()
        supplied = executable.parent.parent / "lib/clang/22/include/omp.h"
        self.assertTrue(supplied.is_file(), output)
        self.assertEqual(supplied.read_bytes(), header.read_bytes())

    def test_clangd_repairs_existing_managed_install_without_download(self):
        self.clang_fixtures()
        self.run_setup("clangd,clang-tidy")
        executables = {name: (self.home / ".local/bin" / name).resolve()
                       for name in ("clangd", "clang-tidy")}
        (self.home / "fetch-log").unlink()
        header = self.openmp_compiler()
        self.run_setup("clangd,clang-tidy")
        for name, major in (("clangd", "22"), ("clang-tidy", "23")):
            executable = executables[name]
            supplied = executable.parent.parent / ("lib/clang/" + major + "/include/omp.h")
            self.assertTrue(supplied.is_file(), "rerunning setup must repair missing OpenMP headers")
            self.assertEqual(supplied.read_bytes(), header.read_bytes())
            self.assertEqual((self.home / ".local/bin" / name).resolve(), executable)
        self.assertFalse((self.home / "fetch-log").exists())

    def test_clang_headers_use_clang_resource_directory_when_available(self):
        self.clang_fixtures()
        resource = self.base / "clang SDK"
        header = resource / "include/omp.h"
        header.parent.mkdir(parents=True)
        header.write_text("/* clang SDK OpenMP */\n")
        self.env = dict(self.env, CLANG_RESOURCE_DIR=str(resource))
        self.write_bin("clang++", '''#!/bin/sh
case $1 in
    -print-file-name=include) echo include ;;
    -print-resource-dir) printf '%s\\n' "$CLANG_RESOURCE_DIR" ;;
    *) exit 2 ;;
esac
''')
        self.run_setup("clangd")
        executable = (self.home / ".local/bin/clangd").resolve()
        supplied = executable.parent.parent / "lib/clang/22/include/omp.h"
        self.assertTrue(supplied.is_file())
        self.assertEqual(supplied.read_bytes(), header.read_bytes())

    def test_clang_headers_do_not_borrow_gcc_intrinsic_headers(self):
        self.clang_fixtures()
        header = self.openmp_compiler()
        (header.parent / "stdint.h").write_text("/* GCC intrinsic header */\n")
        output = self.run_setup("clangd")
        executable = (self.home / ".local/bin/clangd").resolve()
        include = executable.parent.parent / "lib/clang/22/include"
        self.assertFalse((include / "stdint.h").exists())
        result = next(s for s in output.splitlines() if s.startswith("  clangd:"))
        self.assertIn("stdint.h", result)

    def test_clangd_preserves_bundled_openmp_header(self):
        self.clang_fixtures()
        self.run_setup("clangd")
        executable = (self.home / ".local/bin/clangd").resolve()
        supplied = executable.parent.parent / "lib/clang/22/include/omp.h"
        supplied.write_text("/* upstream OpenMP header */\n")
        self.openmp_compiler()
        self.run_setup("clangd")
        self.assertEqual(supplied.read_text(), "/* upstream OpenMP header */\n")

    def test_clangd_tries_next_compiler_when_openmp_header_is_unavailable(self):
        self.clang_fixtures()
        header = self.openmp_compiler()
        (self.bin / "c++").rename(self.bin / "g++")
        for reply in ("exit 1", "echo include", "echo /missing/include"):
            with self.subTest(reply=reply):
                self.write_bin("c++", "#!/bin/sh\n" + reply + "\n")
                self.run_setup("clangd")
                executable = (self.home / ".local/bin/clangd").resolve()
                supplied = executable.parent.parent / "lib/clang/22/include/omp.h"
                self.assertTrue(supplied.is_file())
                self.assertEqual(supplied.read_bytes(), header.read_bytes())
                shutil.rmtree(self.home / ".local")

    def test_clangd_openmp_copy_failure_cleans_temporary_header_and_continues(self):
        self.clang_fixtures()
        self.openmp_compiler()
        (self.bin / "cp").unlink()
        self.write_bin("cp", "#!/bin/sh\nexit 1\n")
        output = self.run_setup("clangd,path", success=False)
        self.assertIn("clangd: FAILED", output)
        self.assertIn("path: configured", output)
        executable = (self.home / ".local/bin/clangd").resolve()
        include = executable.parent.parent / "lib/clang/22/include"
        self.assertEqual(sorted(p.name for p in include.iterdir()), ["stddef.h"])

    def test_clangd_leaves_unmanaged_install_untouched(self):
        self.clang_fixtures()
        self.openmp_compiler()
        external = self.base / "external/bin/clangd"
        external.parent.mkdir(parents=True)
        external.write_text("#!/bin/sh\nexit 0\n")
        external.chmod(0o755)
        local = self.home / ".local/bin/clangd"
        local.parent.mkdir(parents=True)
        local.symlink_to(external)
        self.run_setup("clangd")
        self.assertEqual(local.resolve(), external.resolve())
        self.assertEqual(sorted(str(p.relative_to(external.parent.parent))
                                for p in external.parent.parent.rglob("*")),
                         ["bin", "bin/clangd"])
        self.assertFalse((self.home / "fetch-log").exists())

    def test_clangd_does_not_repair_link_escaping_managed_directory(self):
        self.clang_fixtures()
        self.openmp_compiler()
        external = self.base / "external"
        (external / "clangd/data/bin").mkdir(parents=True)
        include = external / "clangd/data/lib/clang/22/include"
        include.mkdir(parents=True)
        executable = external / "clangd/data/bin/clangd"
        executable.write_text("#!/bin/sh\nexit 0\n")
        executable.chmod(0o755)
        managed = self.home / ".local/opt/clangd-v22.1.1.0.external"
        managed.parent.mkdir(parents=True)
        managed.symlink_to(external, target_is_directory=True)
        local = self.home / ".local/bin/clangd"
        local.parent.mkdir(parents=True)
        local.symlink_to(managed / "clangd/data/bin/clangd")
        self.run_setup("clangd")
        self.assertEqual(list(include.iterdir()), [])

    def test_clang_failed_probe_removes_stage_and_continues(self):
        self.clang_fixtures(headers_present=False)
        output = self.run_setup("clangd,path", success=False)
        self.assertIn("clangd: FAILED", output)
        self.assertIn("path: configured", output)
        self.assertFalse((self.home / ".local/bin/clangd").exists())
        self.assertEqual(list((self.home / ".local/opt").iterdir()), [])

    def test_clang_checksums_with_macos_shasum(self):
        self.clang_fixtures()
        sha256 = self.bin / "sha256sum"
        if sha256.exists():
            sha256.unlink()
        if not (self.bin / "shasum").exists():
            self.skipTest("shasum is not installed")
        self.assertIn("clangd: installed", self.run_setup("clangd"))

    def test_clang_extracts_with_unzip_when_python_is_unavailable(self):
        unzip = shutil.which("unzip")
        if not unzip:
            self.skipTest("unzip is not installed")
        self.clang_fixtures()
        (self.bin / "unzip").symlink_to(unzip)
        for name in ("docker", "curl"):
            path = self.bin / name
            path.write_text(path.read_text().replace("#!/usr/bin/env python3",
                                                    "#!" + shutil.which("python3")))
        (self.bin / "python3").unlink()
        self.env = dict(self.env, TEST_LIBC="musl")
        self.assertIn("clangd: installed", self.run_setup("clangd"))

    def test_clang_no_extractor_reports_reason_after_checksum_validation(self):
        self.clang_fixtures()
        for name in ("docker", "curl"):
            path = self.bin / name
            path.write_text(path.read_text().replace("#!/usr/bin/env python3",
                                                    "#!" + shutil.which("python3")))
        (self.bin / "python3").unlink()
        output = self.run_setup("clangd,path", success=False)
        self.assertIn("requires unzip or python3", output)
        self.assertIn("path: configured", output)
        (self.base / "assets/clangd.whl").write_bytes(b"corrupt download")
        output = self.run_setup("clangd,path", success=False)
        self.assertIn("checksum mismatch", output)
        self.assertNotIn("requires unzip or python3", output)

    def test_invalid_selection(self):
        self.assertIn("Unknown tool", self.run_setup("bogus", success=False))


if __name__ == "__main__":
    unittest.main()
