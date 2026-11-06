import base64
import hashlib
import socket
import ssl
import subprocess
import tempfile
import threading
import zlib
from pathlib import Path

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as temp:
    tmp = Path(temp)
    key, cert = tmp / 'key.pem', tmp / 'cert.pem'
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                    '-keyout', str(key), '-out', str(cert), '-subj', '/CN=localhost',
                    '-addext', 'subjectAltName=DNS:localhost'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    for hostname, roots, good_accept, expect, auth, *extra in [('localhost', cert, True, True, False),
                                                   ('localhost', cert, True, True, True),
                                                   ('localhost', cert, True, True, False, True),
                                                   ('localhost', cert, True, True, False, False, True),
                                                   ('wrong.invalid', cert, True, False, False),
                                                   ('localhost', '/dev/null', True, False, False),
                                                   ('localhost', cert, False, False, False)]:
        listener = socket.socket()
        listener.bind(('127.0.0.1', 0))
        listener.listen(1)
        listener.settimeout(5)
        errors = []
        omit_protocol = len(extra) > 1 and extra[1]
        def serve():
            try:
                peer, _ = listener.accept()
                peer.settimeout(5)
                with context.wrap_socket(peer, server_side=True) as stream:
                    data = b''
                    while b'\r\n\r\n' not in data:
                        data += stream.recv(1)
                    headers = dict(line.split(b':', 1) for line in data.split(b'\r\n')[1:] if b':' in line)
                    key_value = headers[b'Sec-WebSocket-Key'].strip()
                    accept = base64.b64encode(hashlib.sha1(key_value + b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest())
                    if not good_accept:
                        accept = b'invalid'
                    stream.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n' + (b'' if omit_protocol else b'Sec-WebSocket-Protocol: app\r\n') + b'Sec-WebSocket-Accept: ' + accept + b'\r\n\r\n')
                    if good_accept and expect:
                        header = stream.recv(2)
                        remaining = header[1]
                        payload = b''
                        while len(payload) < remaining:
                            payload += stream.recv(remaining - len(payload))
                        document = zlib.decompress(payload[4:], -15)
                        if auth:
                            assert document == b'[1,"ml","login","secret",1,123]'
                            response = b'[1,0,123,"testkey"]'
                        else:
                            assert document == b'[1,"fi"]'
                            response = b'[1,0]'
                        stream.sendall(bytes([0x82, len(response)]) + response)
                        if auth:
                            header = stream.recv(2)
                            payload = b''
                            while len(payload) < header[1]:
                                payload += stream.recv(header[1] - len(payload))
                            assert zlib.decompress(payload[4:], -15) == b'[2,"ma",123,"testkey",1]'
                            stream.sendall(b'\x82\x05[2,0]')
            except (ssl.SSLError, ConnectionError, OSError) as exc:
                if expect:
                    errors.append(exc)
            finally:
                listener.close()
        thread = threading.Thread(target=serve)
        thread.start()
        result = subprocess.run([str(root / 'build/test_tls_client'), str(listener.getsockname()[1]),
                                 hostname, str(roots), str(int(expect)), str(int(auth))] + ([str(int(extra[0]))] if extra else []), timeout=8)
        thread.join(timeout=8)
        assert result.returncode == 0 and not thread.is_alive() and not errors, (hostname, result.returncode, errors)
print('tls tests passed')
