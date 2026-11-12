#!/usr/bin/env python3
"""Loopback-only mobile UI preview. Does not connect to or impersonate an OS backend."""
import argparse
import json
import mimetypes
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

PUBLIC = Path(__file__).resolve().parents[1] / 'public'
MESSAGE = 'Local interface preview. Connect this frontend to the k-hole OS gateway for live features.'


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, body, status=200, content_type='application/json', headers=None):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(body)

    def unavailable(self):
        self.reply(json.dumps(dict(ok=False, code='PREVIEW_ONLY', error=MESSAGE, message=MESSAGE)).encode(), 503)

    def do_GET(self):
        path = unquote(urlsplit(self.path).path)
        if any(path == prefix or path.startswith(prefix+'/') for prefix in ('/api','/app','/beam/api','/agents/api')):
            return self.unavailable()
        if path in ('/remote','/beam','/agents','/assistant'):
            return self.reply(b'', 308, headers={'Location': path+'/'})
        target = (PUBLIC / path.lstrip('/')).resolve()
        if not target.is_relative_to(PUBLIC.resolve()):
            return self.reply(b'{"error":"not found"}',404)
        if target.is_dir():
            target = target / 'index.html'
        if not target.is_file():
            return self.reply(b'{"error":"not found"}',404)
        body = target.read_bytes()
        if target.name == 'index.html' and target.parent.name in ('remote','beam','agents'):
            body = body.replace(b'href="manifest.webmanifest"',b'href="/manifest.webmanifest"',1)
            body = body.replace(b'{{NAME}}',b'Local preview')
        content_type = {'.js':'text/javascript; charset=utf-8', '.webmanifest':'application/manifest+json',
                        '.html':'text/html; charset=utf-8', '.css':'text/css; charset=utf-8',
                        '.woff2':'font/woff2'}.get(target.suffix, mimetypes.guess_type(target.name)[0] or 'application/octet-stream')
        self.reply(body,content_type=content_type)

    do_HEAD = do_GET
    do_POST = unavailable
    do_PUT = unavailable
    do_PATCH = unavailable
    do_DELETE = unavailable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',type=int,default=4173)
    args = parser.parse_args()
    with ThreadingHTTPServer(('127.0.0.1',args.port),Handler) as server:
        print('Local mobile preview: http://127.0.0.1:%d' % server.server_port,flush=True)
        print(MESSAGE,flush=True)
        try: server.serve_forever()
        except KeyboardInterrupt: pass


if __name__ == '__main__':
    main()
