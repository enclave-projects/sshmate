# Copyright 2026 SSH Mate contributors
# SPDX-License-Identifier: GPL-3.0-only
"""Loopback-only SSH/SFTP fixture. Requires Python's paramiko package."""
import os
import io
import json
import socket
import threading
import tempfile
import paramiko

ROOT = tempfile.TemporaryDirectory()
KEY = paramiko.RSAKey.generate(2048)
CLIENT_KEY = paramiko.RSAKey.generate(2048)

class Server(paramiko.ServerInterface):
    def __init__(self):
        self.targets = {}

    def check_channel_direct_tcpip_request(self, channel_id, origin, destination):
        if destination[0] != '127.0.0.1':
            return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED
        self.targets[channel_id] = destination
        return paramiko.OPEN_SUCCEEDED

    def check_auth_password(self, username, password):
        return paramiko.AUTH_SUCCESSFUL if (username, password) == ('fixture', 'test-only') else paramiko.AUTH_FAILED

    def get_allowed_auths(self, username):
        return 'publickey,password'

    def check_auth_publickey(self, username, key):
        return paramiko.AUTH_SUCCESSFUL if username == 'fixture' and key == CLIENT_KEY else paramiko.AUTH_FAILED

    def check_channel_request(self, kind, channel_id):
        return paramiko.OPEN_SUCCEEDED if kind == 'session' else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

    def check_channel_pty_request(self, *args):
        return True

    def check_channel_window_change_request(self, *args):
        return True

    def check_channel_shell_request(self, channel):
        def echo():
            channel.send(b'fixture-ready\r\n')
            try:
                while True:
                    data = channel.recv(65536)
                    if not data:
                        break
                    channel.send(data)
            finally:
                channel.close()
        threading.Thread(target=echo, daemon=True).start()
        return True

class Handle(paramiko.SFTPHandle):
    def stat(self):
        return paramiko.SFTPAttributes.from_stat(os.fstat(self.readfile.fileno()))

class Files(paramiko.SFTPServerInterface):
    def local(self, path):
        candidate = os.path.abspath(os.path.join(ROOT.name, path.lstrip('/')))
        if os.path.commonpath([ROOT.name, candidate]) != ROOT.name:
            raise OSError('Outside fixture')
        return candidate

    def canonicalize(self, path):
        return '/' if path == '.' else '/' + path.strip('/')

    def list_folder(self, path):
        try:
            result = []
            for name in os.listdir(self.local(path)):
                attrs = paramiko.SFTPAttributes.from_stat(os.stat(os.path.join(self.local(path), name)))
                attrs.filename = name
                result.append(attrs)
            return result
        except OSError as error:
            return paramiko.SFTPServer.convert_errno(error.errno)

    def stat(self, path):
        try:
            return paramiko.SFTPAttributes.from_stat(os.stat(self.local(path)))
        except OSError as error:
            return paramiko.SFTPServer.convert_errno(error.errno)

    lstat = stat

    def open(self, path, flags, attrs):
        try:
            descriptor = os.open(self.local(path), flags, 0o600)
            mode = 'r+b' if flags & os.O_RDWR else 'wb' if flags & os.O_WRONLY else 'rb'
            stream = os.fdopen(descriptor, mode)
            handle = Handle(flags)
            handle.readfile = stream
            handle.writefile = stream
            return handle
        except OSError as error:
            return paramiko.SFTPServer.convert_errno(error.errno)

    def mkdir(self, path, attrs):
        os.mkdir(self.local(path))
        return paramiko.SFTP_OK

    def rmdir(self, path):
        os.rmdir(self.local(path))
        return paramiko.SFTP_OK

    def remove(self, path):
        os.remove(self.local(path))
        return paramiko.SFTP_OK

    def rename(self, old, new):
        os.rename(self.local(old), self.local(new))
        return paramiko.SFTP_OK

def serve(client):
    transport = paramiko.Transport(client)
    transport.add_server_key(KEY)
    transport.set_subsystem_handler('sftp', paramiko.SFTPServer, Files)
    try:
        server = Server()
        transport.start_server(server=server)
        while transport.is_active():
            channel = transport.accept(0.1)
            if channel and channel.get_id() in server.targets:
                target = socket.create_connection(server.targets[channel.get_id()])
                def pump(source, destination):
                    try:
                        while True:
                            data = source.recv(65536)
                            if not data:
                                break
                            destination.sendall(data)
                    except OSError:
                        pass
                    finally:
                        source.close()
                        destination.close()
                threading.Thread(target=pump, args=(channel, target), daemon=True).start()
                threading.Thread(target=pump, args=(target, channel), daemon=True).start()
    except (EOFError, paramiko.SSHException):
        pass
    finally:
        transport.close()

listener = socket.socket()
listener.bind(('127.0.0.1', 0))
listener.listen()
private_key = io.StringIO()
CLIENT_KEY.write_private_key(private_key)
print(json.dumps({'port': listener.getsockname()[1], 'privateKey': private_key.getvalue()}), flush=True)
while True:
    client, _ = listener.accept()
    threading.Thread(target=serve, args=(client,), daemon=True).start()
