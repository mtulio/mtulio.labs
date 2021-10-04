from flask import Flask
from flask import request
from flask import jsonify
app = Flask(__name__)

@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def catch_all(path):
    resp = {}
    try:
        resp['data'] = str(request.data)
    except KeyError:
        resp['data'] = 'request.data Not Found'
    except Exception as e:
        resp['data'] = 'ERROR: {}'.format(e)

    try:
        resp['args'] = request.args
    except KeyError:
        resp['args'] = 'request.args Not Found'
    except Exception as e:
        resp['args'] = 'ERROR: {}'.format(e)

    try:
        resp['headers'] = str(request.headers)
    except KeyError:
        resp['headers'] = 'request.headers Not Found'
    except Exception as e:
        resp['headers'] = 'ERROR: {}'.format(e)

    try:
        resp['json'] = request.json()
    except KeyError:
        resp['json'] = 'request.json() Not Found'
    except Exception as e:
        resp['json'] = 'ERROR: {}'.format(e)

    return jsonify(resp)
