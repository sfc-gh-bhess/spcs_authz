import logging

from flask import Flask, jsonify, make_response, send_file, request

logging.basicConfig(level=logging.INFO)

app = Flask(__name__)

@app.route("/")
def default():
    return make_response(jsonify(result='Nothing to see here'))

@app.route("/test")
def tester():
    return send_file("api_test.html")

@app.route("/headers")
def headers():
    return make_response(jsonify(dict(request.headers)))

@app.errorhandler(404)
def resource_not_found(e):
    return make_response(jsonify(error='Not found!'), 404)

if __name__ == '__main__':
    app.run(port=8001, host='0.0.0.0')
