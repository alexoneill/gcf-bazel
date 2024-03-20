import cowsay

# Primary entrypoint for the echo server.
def main(request):
  '''Responds to any HTTP request.

  Args:
    request (flask.Request): HTTP request object.

  Returns:
    The response text or any set of values that can be turned into a Response
    object using 'flask.Flask.make_response'
  '''
  return cowsay.cow(request.get_data())
