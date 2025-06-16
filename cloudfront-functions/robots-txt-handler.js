function handler(event) {
  var request = event.request;
  var uri = request.uri;

  if (uri === '/robots.txt') {
    var response = {
      statusCode: 404,
      statusDescription: 'Not Found',
      headers: {
          'content-type': {
              value: 'text/plain'
          }
      }
    };
    return response;
  }

  // Otherwise, proceed with original request
  return request;
}
