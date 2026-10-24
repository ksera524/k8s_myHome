#!/usr/bin/env python3
"""同じS3 objectを読み、経路別の待ち時間と転送速度を比較する（書き込みなし）。"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import http.client
import json
import math
import ssl
import time
from urllib.parse import quote, urlsplit


def connection(url, connect_override=None, ca_file=None):
    parsed = urlsplit(url)
    if parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username:
        raise ValueError('invalid endpoint')
    if connect_override:
        # port-forward先へ接続しても、署名対象のHost/path/queryは変更しない。
        if parsed.scheme != 'http':
            raise ValueError('connect override supports HTTP port-forward only')
        host, port = connect_override.rsplit(':', 1)
        client = http.client.HTTPConnection(host, int(port), timeout=60)
    elif parsed.scheme == 'https':
        client = http.client.HTTPSConnection(parsed.hostname, parsed.port, timeout=60,
                                           context=ssl.create_default_context(cafile=ca_file))
    else:
        client = http.client.HTTPConnection(parsed.hostname, parsed.port, timeout=60)
    return client, parsed


def post(base, path, payload, ca_file):
    client, parsed = connection(base.rstrip('/') + path, ca_file=ca_file)
    try:
        client.request('POST', parsed.path, json.dumps(payload), {'Content-Type': 'application/json'})
        response = client.getresponse()
        if response.status != 200:
            raise RuntimeError(f'API status {response.status}')
        return json.loads(response.read())
    finally:
        client.close()


def measure(url, byte_range, connect_override, ca_file):
    client, parsed = connection(url, connect_override, ca_file)
    headers = {'Host': parsed.netloc, 'Accept-Encoding': 'identity'}
    if byte_range:
        headers['Range'] = byte_range
    start = time.monotonic()
    try:
        client.request('GET', parsed.path + ('?' + parsed.query if parsed.query else ''), headers=headers)
        response = client.getresponse()
        headers_ms = (time.monotonic() - start) * 1000
        expected_status = 206 if byte_range else 200
        if response.status != expected_status:
            return {'status': response.status, 'error': f'expected {expected_status}'}
        first = response.read(1)
        first_byte_ms = (time.monotonic() - start) * 1000
        digest = hashlib.sha256(first)
        size = len(first)
        while chunk := response.read(64 * 1024):
            size += len(chunk)
            digest.update(chunk)
        elapsed = time.monotonic() - start
        return {'status': response.status, 'bytes': size, 'sha256': digest.hexdigest(),
                'headers_ms': round(headers_ms, 2), 'first_byte_ms': round(first_byte_ms, 2),
                'total_ms': round(elapsed * 1000, 2),
                'mib_per_second': round(size / 1024**2 / elapsed, 2)}
    except Exception as error:
        # URLには署名が含まれるため、例外本文を表示しない。
        return {'error': type(error).__name__}
    finally:
        client.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--api', required=True)
    parser.add_argument('--gateway', required=True)
    parser.add_argument('--bucket', required=True)
    parser.add_argument('--key', action='append', required=True)
    parser.add_argument('--s3-connect', help='RustFS port-forward先。例: 127.0.0.1:19000')
    parser.add_argument('--ca-file')
    parser.add_argument('--iterations', type=int, default=5)
    parser.add_argument('--concurrency', type=int, default=1)
    args = parser.parse_args()
    if not 1 <= args.iterations <= 100 or not 1 <= args.concurrency <= 8:
        parser.error('iterations must be 1..100 and concurrency 1..8')
    failed = False
    for key in args.key:
        signed = post(args.api, '/s3/presigned_get_object',
                      {'bucket': args.bucket, 'key': key, 'expires_in_secs': 3600}, args.ca_file)
        if signed.get('method', 'GET') != 'GET':
            raise ValueError('expected signed GET')
        path = '/s3/preview/' + quote(args.bucket, safe='') + '/' + quote(key, safe='/')
        routes = [('s3', signed['url'], args.s3_connect),
                  ('api', args.api.rstrip('/') + path, None),
                  ('gateway', args.gateway.rstrip('/') + path, None)]
        for byte_range in ('bytes=0-1048575', None):
            fingerprints = set()
            for name, url, override in routes:
                with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
                    samples = list(pool.map(lambda _: measure(url, byte_range, override, args.ca_file),
                                            range(args.iterations)))
                valid = [sample for sample in samples if 'error' not in sample]
                fingerprints.update((sample['bytes'], sample['sha256']) for sample in valid)
                summary = {}
                for field in ('first_byte_ms', 'total_ms', 'mib_per_second'):
                    values = sorted(sample[field] for sample in valid)
                    if values:
                        summary[field] = {label: values[max(0, math.ceil(len(values) * p) - 1)]
                                          for label, p in [('p50', .5), ('p95', .95)]}
                failed |= len(valid) != len(samples)
                print(json.dumps({'object_id': hashlib.sha256(key.encode()).hexdigest()[:12],
                                  'kind': key.rsplit('.', 1)[-1], 'route': name,
                                  'range': byte_range, 'concurrency': args.concurrency,
                                  'summary': summary, 'samples': samples}), flush=True)
            if len(fingerprints) != 1:
                print(json.dumps({'error': 'content differs between routes or requests'}), flush=True)
                failed = True
    raise SystemExit(1 if failed else 0)


if __name__ == '__main__':
    main()
