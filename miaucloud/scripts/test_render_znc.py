import json
import os
from pathlib import Path
import tempfile
import unittest

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
        render(self.template, self.secret_file, self.target, os.geteuid(), os.getegid())

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

    def test_rejects_readable_secrets_without_replacing_target(self):
        self.secret_file.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "0600"):
            self.render()
        self.assertEqual(self.target.read_text(), "previous configuration")

    def test_rejects_template_mismatch_without_replacing_target(self):
        self.template.write_text("@PASSWORD_HASH@\n@SAVEBUFF_KEY@")
        with self.assertRaisesRegex(ValueError, "placeholders"):
            self.render()
        self.assertEqual(self.target.read_text(), "previous configuration")


if __name__ == "__main__":
    unittest.main()
