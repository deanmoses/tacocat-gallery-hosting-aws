/**
 * Returns a proper 404 for /robots.txt requests.
 *
 * Problem: This SPA returns index.html with a 200 status for all unknown paths,
 * including /robots.txt. Crawlers see HTML content instead of a proper 404.
 *
 * Solution: This CloudFront Function intercepts /robots.txt at the edge and
 * returns a real 404 before the request ever hits S3 or the SPA fallback.
 *
 * Note: Actual search engine indexing prevention is handled by the
 * <meta name="robots" content="noindex"> tag in the SvelteKit app.
 * This function just fixes the incorrect 200 status for robots.txt.
 */
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
