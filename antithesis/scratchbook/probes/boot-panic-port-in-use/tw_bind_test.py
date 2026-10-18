# Does a TIME_WAIT left by an outgoing connection on local port P block a listener bind on 0.0.0.0:P
# when the listener sets SO_REUSEADDR (as tokio/mio do) but the client socket did not (as curl/hyper don't)?
import socket, time, errno
P = 50100
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); srv.bind(("127.0.0.1", 0)); srv.listen(1)
cli = socket.socket()
cli.bind(("0.0.0.0", P))          # stand-in for the kernel picking P as the ephemeral port
cli.connect(srv.getsockname()); conn, _ = srv.accept()
cli.close(); time.sleep(0.2); conn.close(); time.sleep(0.2)   # client closes first -> TIME_WAIT on port P
import subprocess; print(subprocess.run(["ss","-tan","sport","=",f":{P}"],capture_output=True,text=True).stdout.strip())
lst = socket.socket(); lst.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    lst.bind(("0.0.0.0", P)); lst.listen(); print("bind ok with SO_REUSEADDR")
except OSError as e:
    print("bind failed:", errno.errorcode[e.errno])
