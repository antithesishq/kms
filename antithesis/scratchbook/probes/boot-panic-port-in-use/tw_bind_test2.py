# Same as tw_bind_test.py, but the kernel picks the client's port itself (ephemeral range narrowed to 50100-50101
# in a private network namespace), as for an ordinary outgoing HTTP connection.
import socket, time, errno, subprocess
P = 50100
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); srv.bind(("127.0.0.1", 9000)); srv.listen(1)
cli = socket.socket(); cli.connect(("127.0.0.1", 9000)); conn, _ = srv.accept()
print("client local port:", cli.getsockname()[1])
cli.close(); time.sleep(0.2); conn.close(); time.sleep(0.2)
print(subprocess.run(["ss","-tan"],capture_output=True,text=True).stdout.strip())
for i in range(2):
    lst = socket.socket(); lst.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        lst.bind(("0.0.0.0", P)); lst.listen(); print("bind ok"); break
    except OSError as e:
        print("bind 0.0.0.0:%d failed:" % P, errno.errorcode[e.errno]); lst.close(); time.sleep(1)
