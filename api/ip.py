# from flask import Flask, Response, request
# from flask import jsonify
# app = Flask(__name__)

# @app.route('/', defaults={'path': ''})
# @app.route('/<path:path>')
# def catch_all(path):
#     jsonResp = False
#     try:
#         ipaddr = request.headers.get('X-Forwarded-For')
#     except KeyError:
#         ipaddr = request.headers.get('X-Real-Ip')
#     except Exception as e:
#         ipaddr = 'NotFound: {}'.format(e)

#     try:
#         if 'json' in request.args:
#             jsonResp = True
#     except Exception as e:
#         print("Error getting arg json: ", e)

#     if jsonResp:
#         return jsonify({
#             "ip": ipaddr,
#             "ipv4": ipaddr
#         })
#     else:
#         return Response("""%s
# """ % (ipaddr), mimetype="text/plain")

from http.server import BaseHTTPRequestHandler
from datetime import datetime

class handler(BaseHTTPRequestHandler):

  def do_GET(self):
    self.send_response(200)
    self.send_header('Content-type', 'text/plain')
    self.end_headers()
    self.wfile.write(str(datetime.now().strftime('%Y-%m-%d %H:%M:%S')).encode())
    elf.wfile.write(str(self.client_address).encode())
    return
