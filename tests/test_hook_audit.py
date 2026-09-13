import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("audit", Path(__file__).resolve().parents[1] / "tools/audit_ipa_hooks.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class HookAuditTests(unittest.TestCase):
    def test_missing_app_selectors_are_not_inherited_system_methods(self):
        with tempfile.TemporaryDirectory() as directory:
            audit.SOURCE = Path(directory)
            hooks = audit.SOURCE / "src/Hooks"
            hooks.mkdir(parents=True)
            (hooks / "Likes.x").write_text('''%hook ActivityController
- (NSInteger)numberOfTabsV1In:(id)sender { return %orig; }
- (NSInteger)numberOfTabsIn:(id)sender { return %orig; }
- (void)viewDidLayoutSubviews { %orig; }
%new
- (void)tweakAddition { }
%end
%hook AppModel
- (BOOL)removedFeature { return %orig; }
%end
''')
            native = {'types': 'q24@0:8@16', 'address': 123}
            result = audit.hooks({'classes': {
                'ActivityController': {'superclass': 'UIViewController', 'methods': {'-numberOfTabsIn:': native}},
                'AppModel': {'superclass': 'NSObject', 'methods': {}}
            }})
            self.assertEqual([r['status'] for r in result],
                             ['missing-method', 'present', 'system-runtime', 'new', 'missing-method'])


if __name__ == '__main__':
    unittest.main()
