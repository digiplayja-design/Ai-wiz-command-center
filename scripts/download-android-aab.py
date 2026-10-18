#!/usr/bin/env python3
"""Serve one completed Android bundle through a private Codespaces port."""
import argparse
import html
import shutil
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--build-number', type=int, required=True)
    parser.add_argument('--port', type=int, default=8789)
    args = parser.parse_args()
    bundle = args.bundle.resolve(strict=True)
    if not 0 < args.build_number < 2100000000 or not 1024 <= args.port <= 65535:
        parser.error('Enter the completed build number and an unprivileged port.')
    if not bundle.is_file() or bundle.suffix != '.aab':
        parser.error('Select the completed .aab file.')
    with zipfile.ZipFile(bundle) as archive:
        if 'base/manifest/AndroidManifest.xml' not in archive.namelist() or archive.testzip():
            parser.error('The file is not an intact Android bundle.')
    filename = f'KORLIX-{args.build_number}.aab'
    page = (
        '<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>Save KORLIX Android build</title><h1>Save your Android build</h1>'
        f'<p><a download="{filename}" href="/{filename}">Download {html.escape(filename)}</a></p>'
        '<p>On iPad, choose Save to Files and select Downloads. '
        'Keep this terminal running until the download finishes.</p>'
    ).encode()

    class Download(BaseHTTPRequestHandler):
        def send_file(self, body):
            path = urlsplit(self.path).path
            if path not in ('/', '/' + filename):
                self.send_error(404)
                return
            is_bundle = path != '/'
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream' if is_bundle else 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(bundle.stat().st_size if is_bundle else len(page)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            if is_bundle:
                self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
            self.end_headers()
            if body:
                try:
                    if is_bundle:
                        with bundle.open('rb') as source:
                            shutil.copyfileobj(source, self.wfile, length=1024 * 1024)
                    else:
                        self.wfile.write(page)
                except (BrokenPipeError, ConnectionResetError):
                    pass

        def do_GET(self):
            self.send_file(True)

        def do_HEAD(self):
            self.send_file(False)

    print(f'Serving {filename} ({bundle.stat().st_size:,} bytes).', flush=True)
    print(f'Codespaces: open Ports, forward {args.port}, keep visibility Private, then Open in Browser.', flush=True)
    print('The download name uses the build number you supplied. Confirm that number in the build output.', flush=True)
    print('Press Ctrl+C after the file is saved. Only this bundle is served.', flush=True)
    with ThreadingHTTPServer(('127.0.0.1', args.port), Download) as server:
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == '__main__':
    main()
