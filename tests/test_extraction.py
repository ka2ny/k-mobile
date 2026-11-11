import hashlib
import importlib.util
import json
from html.parser import HTMLParser
from pathlib import Path
import re
import subprocess
import threading
import unittest
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen
from urllib.error import HTTPError

ROOT=Path(__file__).resolve().parents[1]
PUBLIC=ROOT/'public'
spec=importlib.util.spec_from_file_location('preview',ROOT/'scripts/serve.py')
preview=importlib.util.module_from_spec(spec);spec.loader.exec_module(preview)

class References(HTMLParser):
    def __init__(self):super().__init__();self.paths=[]
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if tag in ('script','img','source') and attrs.get('src'):self.paths.append(attrs['src'])
        if tag=='link' and attrs.get('href'):self.paths.append(attrs['href'])

class Extraction(unittest.TestCase):
    def exists(self,reference,source):
        url=urlsplit(urljoin('http://local/'+str(source.relative_to(PUBLIC)),reference))
        if url.netloc!='local':return
        target=PUBLIC/url.path.lstrip('/')
        self.assertTrue(target.is_file(),f'{source.relative_to(PUBLIC)} -> {reference}')

    def test_upstream_files_are_exact(self):
        manifest=json.loads((ROOT/'source.json').read_text())
        for entry in manifest['files']:
            self.assertEqual(hashlib.sha256((ROOT/entry['path']).read_bytes()).hexdigest(),entry['sha256'],entry['path'])

    def test_html_css_and_manifest_dependencies(self):
        for source in PUBLIC.rglob('*.html'):
            parser=References();parser.feed(source.read_text())
            for reference in parser.paths:self.exists(reference,source)
        for source in PUBLIC.rglob('*.css'):
            for reference in re.findall(r'url\([\'"]?([^\)\'"\s]+)',source.read_text()):
                if not reference.startswith('data:'):self.exists(reference,source)
        for source in PUBLIC.rglob('*.webmanifest'):
            manifest=json.loads(source.read_text())
            for icon in manifest['icons']:self.exists(icon['src'],source)

    def test_javascript_and_worker_cache_closure(self):
        subprocess.run(['node',str(ROOT/'tests/assets.cjs')],check=True)

    def test_http_routes_and_backend_boundary(self):
        server=preview.ThreadingHTTPServer(('127.0.0.1',0),preview.Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        base='http://127.0.0.1:'+str(server.server_port)
        try:
            for path in ('/','/remote/','/beam/','/agents/','/assistant/'):
                with urlopen(base+path) as response:
                    self.assertEqual(response.status,200)
                    self.assertIn(b'<html',response.read())
            for path in ('/api/hello','/app/status','/beam/api/me','/agents/api/status','/app/assistant'):
                with self.assertRaises(HTTPError) as failure:urlopen(base+path)
                self.assertEqual(failure.exception.code,503)
                self.assertEqual(json.loads(failure.exception.read())['code'],'PREVIEW_ONLY')
                failure.exception.close()
            with self.assertRaises(HTTPError) as failure:urlopen(Request(base+'/api/pair',data=b'{}'))
            self.assertEqual(failure.exception.code,503);failure.exception.close()
            for path in ('/%2e%2e/source.json','/.git/config','/unknown'):
                with self.assertRaises(HTTPError) as failure:urlopen(base+path)
                self.assertEqual(failure.exception.code,404);failure.exception.close()
            with urlopen(Request(base+'/beam/icon.svg',method='HEAD')) as response:
                self.assertEqual(response.status,200);self.assertEqual(response.read(),b'')
        finally:server.shutdown();server.server_close();thread.join()
