"""The site's pages, after import_opensloper (opensloper-make.sh site runs both)."""
from django.test import SimpleTestCase

from .context import version


class PagesTest(SimpleTestCase):
    def test_home_offers_the_app_and_the_download(self):
        page = self.client.get("/")
        self.assertEqual(page.status_code, 200)
        self.assertContains(page, 'href="/design/"')
        self.assertContains(page, 'href="/measurements/"')
        self.assertContains(page, f"Download {version()}")
        self.assertContains(page, "Beta")
        # The logo and drawings are inlined from the checkout
        self.assertContains(page, "<svg", count=None)

    def test_imported_version(self):
        self.assertRegex(version(), r"^\d+\.\d+\.\d+")

    def test_app_needs_its_slash(self):
        page = self.client.get("/design")
        self.assertEqual(page.status_code, 301)
        self.assertEqual(page["Location"], "/design/")

    def test_app_is_served_while_developing(self):
        with self.settings(DEBUG=True):
            page = self.client.get("/design/")
            self.assertEqual(page.status_code, 200)
            self.assertIn(b'src="main.js"', b"".join(page.streaming_content))

    def test_measurements_app(self):
        page = self.client.get("/measurements")
        self.assertEqual(page.status_code, 301)
        self.assertEqual(page["Location"], "/measurements/")
        with self.settings(DEBUG=True):
            page = self.client.get("/measurements/")
            self.assertEqual(page.status_code, 200)
            self.assertIn(b"OpenSloper Measurements", b"".join(page.streaming_content))
            engine = self.client.get("/measurements/engine_lib.wasm")
            self.assertEqual(engine.status_code, 200)
            self.assertEqual(engine["Content-Type"], "application/wasm")

    def test_search_engine_files(self):
        self.assertContains(self.client.get("/robots.txt"), "Sitemap: https://www.opensloper.com/sitemap.xml")
        self.assertContains(self.client.get("/sitemap.xml"), "https://www.opensloper.com/design/")
        self.assertEqual(self.client.get("/favicon.svg")["Content-Type"], "image/svg+xml")
