from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]

NGINX_CONFIGS = [
    REPO_ROOT / "app/nginx/nginx.conf",
    REPO_ROOT / "app/nginx/nginx.prod.conf",
    REPO_ROOT / "k8s/charts/trinity-platform/templates/configmaps.yaml",
]
NGINX_DEPLOYMENT_TEMPLATE = REPO_ROOT / "k8s/charts/trinity-platform/templates/nginx.yaml"

BOOTSTRAP_RULE = (
    r"location ~* ^/(index\.html|flutter\.js|main\.dart\.js|flutter_bootstrap\.js|"
    r"flutter_service_worker\.js|version\.json|trinity-version\.json)$ {"
)
SPA_FALLBACK_RULE = "location / {"
OLD_COMBINED_ASSET_RULE = r"location ~* \.(ttf|otf|woff|woff2|eot|svg|png|jpg|ico)$ {"
FONT_RULE = r"location ~* \.(ttf|otf|woff|woff2|eot)$ {"
IMAGE_RULE = r"location ~* \.(svg|png|jpg|ico)$ {"


class FrontendCachePolicyTests(unittest.TestCase):
    def _location_block(self, text: str, location_line: str) -> str:
        start = text.find(location_line)
        self.assertNotEqual(start, -1, f"Missing location block: {location_line}")

        brace_start = text.find("{", start)
        self.assertNotEqual(brace_start, -1, f"Missing opening brace for: {location_line}")

        depth = 0
        for index in range(brace_start, len(text)):
            char = text[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    return text[start : index + 1]

        self.fail(f"Unterminated location block: {location_line}")

    def test_agent_docs_do_not_require_hard_refresh(self) -> None:
        agents_md = (REPO_ROOT / "app/AGENTS.md").read_text()

        self.assertNotIn("Then hard-refresh browser: Ctrl+Shift+R.", agents_md)

    def test_nginx_configs_keep_bootstrap_files_uncached(self) -> None:
        for path in NGINX_CONFIGS:
            text = path.read_text()
            bootstrap_block = self._location_block(text, BOOTSTRAP_RULE)

            self.assertIn(BOOTSTRAP_RULE, text, f"Missing bootstrap rule in {path}")
            self.assertIn(
                'add_header Cache-Control "no-cache, no-store, must-revalidate";',
                bootstrap_block,
                f"Missing bootstrap no-cache header in {path}",
            )
            self.assertIn('add_header Pragma "no-cache";', bootstrap_block)

    def test_nginx_configs_keep_spa_fallback_uncached(self) -> None:
        for path in NGINX_CONFIGS:
            text = path.read_text()
            fallback_block = self._location_block(text, SPA_FALLBACK_RULE)

            self.assertIn("try_files $uri $uri/ /index.html;", fallback_block)
            self.assertIn(
                'add_header Cache-Control "no-cache, no-store, must-revalidate";',
                fallback_block,
            )
            self.assertIn('add_header Pragma "no-cache";', fallback_block)

    def test_nginx_configs_revalidate_javascript_and_wasm(self) -> None:
        js_rule = r"location ~* \.(js|wasm|map)$ {"

        for path in NGINX_CONFIGS:
            text = path.read_text()
            js_block = self._location_block(text, js_rule)

            self.assertIn('add_header Cache-Control "no-cache";', js_block)
            self.assertNotIn("immutable", js_block)

    def test_nginx_configs_split_font_and_image_cache_rules(self) -> None:
        for path in NGINX_CONFIGS:
            text = path.read_text()
            font_block = self._location_block(text, FONT_RULE)
            image_block = self._location_block(text, IMAGE_RULE)

            self.assertNotIn(
                OLD_COMBINED_ASSET_RULE,
                text,
                f"Old combined asset cache rule still present in {path}",
            )
            self.assertIn(FONT_RULE, text, f"Missing font cache rule in {path}")
            self.assertIn(IMAGE_RULE, text, f"Missing image cache rule in {path}")
            self.assertIn(
                'add_header Cache-Control "public, max-age=31536000, immutable";',
                font_block,
                f"Missing long-lived font cache header in {path}",
            )
            self.assertIn(
                'add_header Cache-Control "public, max-age=3600";',
                image_block,
                f"Missing 1 hour image cache header in {path}",
            )

    def test_nginx_deployment_rolls_on_config_changes(self) -> None:
        template = NGINX_DEPLOYMENT_TEMPLATE.read_text()

        self.assertIn("checksum/nginx-config:", template)
        self.assertIn("sha256sum", template)


if __name__ == "__main__":
    unittest.main()
