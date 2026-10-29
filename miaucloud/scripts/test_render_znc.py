import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import render_znc
from render_znc import render


class RenderZncTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.template = root / "template"
        self.template.write_text("@PASSWORD_HASH@\n" + "@SAVEBUFF_KEY@\n" * 3)
        self.secret_file = root / "secrets"
        self.secrets = {
            "passwordHash": "$argon2id$v=19$m=6144,t=6,p=1$c2FsdA$aGFzaA",
            "savebuffKey": "a" * 64,
        }
        self.target = root / "znc.conf"
        self.target.write_text("previous configuration")
        self.save_secrets()

    def save_secrets(self):
        self.secret_file.write_text(json.dumps(self.secrets))
        self.secret_file.chmod(0o600)

    def render(self):
        render(self.template, self.secret_file, self.target, 3)

    def test_updates_structure_without_touching_secrets_or_module_state(self):
        module_state = self.target.parent / "module-state"
        module_state.write_bytes(b"retained history")
        original_secrets = self.secret_file.read_bytes()
        self.render()
        self.template.write_text("updated\n" + self.template.read_text())
        self.render()
        self.assertTrue(self.target.read_text().startswith("updated\n$argon2id$"))
        self.assertNotIn("@SAVEBUFF_KEY@", self.target.read_text())
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.secret_file.read_bytes(), original_secrets)
        self.assertEqual(module_state.read_bytes(), b"retained history")

    def test_rejects_configuration_injection_without_replacing_target(self):
        self.secrets["savebuffKey"] += "\nAdmin = true"
        self.save_secrets()
        with self.assertRaisesRegex(ValueError, "savebuff"):
            self.render()
        self.assertEqual(self.target.read_text(), "previous configuration")

    def test_creates_private_files_without_privileged_ownership_calls(self):
        with patch("render_znc.os.fchown", side_effect=PermissionError("Blocked by native sandbox")):
            self.render()
        metadata = self.target.stat()
        self.assertEqual((metadata.st_uid, metadata.st_gid), (os.geteuid(), os.getegid()))
        self.assertEqual(stat.S_IMODE(metadata.st_mode), 0o600)

    def test_rejects_readable_secrets_without_replacing_target(self):
        self.secret_file.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "0600"):
            self.render()
        self.assertEqual(self.target.read_text(), "previous configuration")

    def test_accepts_read_only_systemd_credentials(self):
        self.secret_file.chmod(0o400)
        self.render()
        self.assertIn(self.secrets["passwordHash"], self.target.read_text())

    def test_accepts_acl_protected_root_credentials_only_in_systemd_directory(self):
        metadata = SimpleNamespace(st_mode=stat.S_IFREG | 0o440, st_uid=0, st_gid=0)
        with patch.object(Path, "lstat", return_value=metadata):
            with patch.dict(os.environ, {"CREDENTIALS_DIRECTORY": str(self.secret_file.parent / "other")}):
                with self.assertRaisesRegex(ValueError, "systemd credentials"):
                    self.render()
                self.assertEqual(self.target.read_text(), "previous configuration")
            with patch.dict(os.environ, {"CREDENTIALS_DIRECTORY": str(self.secret_file.parent)}):
                self.render()
        self.assertIn(self.secrets["passwordHash"], self.target.read_text())

    def test_cli_uses_systemd_credentials_for_sasl(self):
        source = self.target.parent / "sasl-example.json"
        source.write_text(json.dumps({"username": "Example", "password": "private password"}))
        source.chmod(0o400)
        destination = self.target.parent / ".registry"
        plan = self.target.parent / "runtime.json"
        plan.write_text(json.dumps({
            "networkCount": 3,
            "sasl": [{"credential": source.name, "target": str(destination)}],
        }))
        self.secret_file.chmod(0o400)
        subprocess.run(
            [
                sys.executable, render_znc.__file__,
                str(self.template), str(self.secret_file), str(self.target), str(plan),
            ],
            env=os.environ | {"CREDENTIALS_DIRECTORY": str(self.target.parent)},
            check=True,
        )
        self.assertIn("username Example\n", destination.read_text())
        self.assertIn(self.secrets["passwordHash"], self.target.read_text())

    def test_rejects_template_mismatch_without_replacing_target(self):
        self.template.write_text("@PASSWORD_HASH@\n@SAVEBUFF_KEY@")
        with self.assertRaisesRegex(ValueError, "placeholders"):
            self.render()
        self.assertEqual(self.target.read_text(), "previous configuration")

    def test_installs_encoded_sasl_credentials_and_requires_authentication(self):
        source = self.target.parent / "sasl.json"
        source.write_text(json.dumps({"username": "Account", "password": "space %;=\u00e9"}))
        source.chmod(0o600)
        destination = self.target.parent / ".registry"
        render(self.template, self.secret_file, self.target, 3, [(source, destination)])
        self.assertEqual(destination.read_text(), (
            "mechanisms PLAIN\n"
            "password space%20;%25;%3b;%3d;%c3;%a9;\n"
            "require%5f;auth yes\n"
            "username Account\n"
        ))
        self.assertEqual(destination.stat().st_mode & 0o777, 0o600)

    def test_invalid_sasl_keeps_existing_configuration_and_registry(self):
        source = self.target.parent / "sasl.json"
        source.write_text(json.dumps({"username": "Account", "password": "bad\npassword"}))
        source.chmod(0o600)
        destination = self.target.parent / ".registry"
        destination.write_text("retained")
        with self.assertRaisesRegex(ValueError, "SASL password"):
            render(self.template, self.secret_file, self.target, 3, [(source, destination)])
        self.assertEqual(destination.read_text(), "retained")
        self.assertEqual(self.target.read_text(), "previous configuration")

    def test_rejects_symlinked_credentials(self):
        link = self.target.parent / "link"
        link.symlink_to(self.secret_file)
        with self.assertRaisesRegex(ValueError, "regular files"):
            render(self.template, link, self.target, 3)

    def test_supports_different_network_counts_without_sasl(self):
        for count in (1, 2, 4):
            with self.subTest(networks=count):
                self.template.write_text("@PASSWORD_HASH@\n" + "@SAVEBUFF_KEY@\n" * count)
                render(self.template, self.secret_file, self.target, count)
                self.assertEqual(self.target.read_text().count(self.secrets["savebuffKey"]), count)

    def test_rejects_empty_network_configuration(self):
        self.template.write_text("@PASSWORD_HASH@\n")
        with self.assertRaisesRegex(ValueError, "placeholders"):
            render(self.template, self.secret_file, self.target, 0)
        self.assertEqual(self.target.read_text(), "previous configuration")

    def test_supports_multiple_sasl_networks(self):
        sources = []
        for name in ("alpha", "beta"):
            source = self.target.parent / f"{name}.json"
            source.write_text(json.dumps({"username": name, "password": name + "-password"}))
            source.chmod(0o600)
            sources.append((source, self.target.parent / f"{name}.registry"))
        render(self.template, self.secret_file, self.target, 3, sources)
        for name, (_, destination) in zip(("alpha", "beta"), sources):
            self.assertIn(f"username {name}\n", destination.read_text())
            self.assertEqual(destination.stat().st_mode & 0o777, 0o600)

    def test_validates_all_sasl_inputs_before_writing_any_registry(self):
        sources = []
        for name, password in (("alpha", "valid"), ("beta", "invalid\npassword")):
            source = self.target.parent / f"{name}.json"
            source.write_text(json.dumps({"username": name, "password": password}))
            source.chmod(0o600)
            destination = self.target.parent / f"{name}.registry"
            destination.write_text("retained")
            sources.append((source, destination))
        with self.assertRaisesRegex(ValueError, "SASL password"):
            render(self.template, self.secret_file, self.target, 3, sources)
        self.assertTrue(all(destination.read_text() == "retained" for _, destination in sources))
        self.assertEqual(self.target.read_text(), "previous configuration")


if __name__ == "__main__":
    unittest.main()
