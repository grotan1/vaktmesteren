import 'dart:convert';
import 'package:http/http.dart' as http;

/// Simple Portainer client helpers used by ops scripts.
class PortainerClient {
  final Uri baseUri;
  final Map<String, String> _headers;

  PortainerClient._(this.baseUri, this._headers);

  /// Create a client using an existing token (e.g. token stored on a user).
  factory PortainerClient.withToken(String baseUrl, String token) {
    final uri = Uri.parse(baseUrl);
    // Portainer supports both JWT bearer tokens and API keys. API keys in
    // Portainer often start with the prefix `ptr_` (example: `ptr_...`). If
    // the provided token looks like an API key, send it with the
    // `X-API-Key` header per Portainer docs. Otherwise use Authorization.
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token.startsWith('ptr_')) {
      headers['X-API-Key'] = token;
    } else {
      headers['Authorization'] = 'Bearer $token';
    }
    return PortainerClient._(uri, headers);
  }

  /// Login using username/password and return a client with the bearer token.
  /// This calls Portainer's `/api/auth` endpoint to obtain a JWT token.
  // Note: We intentionally do not provide a helper that exchanges username+password
  // for a token. The preferred workflow is to store a user token in a secure
  // store and create a client with `PortainerClient.withToken`.

  Uri _build(String path) => baseUri.resolve(path);

  Future<http.Response> get(String path) =>
      http.get(_build(path), headers: _headers);

  Future<http.Response> post(String path, Object? body) => http.post(
        _build(path),
        headers: _headers,
        body: body == null ? null : jsonEncode(body),
      );

  Future<http.Response> put(String path, Object? body) => http.put(
        _build(path),
        headers: _headers,
        body: body == null ? null : jsonEncode(body),
      );

  Future<http.Response> delete(String path) =>
      http.delete(_build(path), headers: _headers);

  /// Helper to fetch a service by id
  Future<Map<String, dynamic>> getService(int endpointId, int serviceId) async {
    final res =
        await get('/api/endpoints/$endpointId/docker/services/$serviceId');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Helper to update a service spec (PUT). The caller must pass the full spec body
  /// as expected by the Portainer HTTP API.
  Future<http.Response> updateService(
      int endpointId, int serviceId, Map<String, dynamic> spec) async {
    return put(
        '/api/endpoints/$endpointId/docker/services/$serviceId/update', spec);
  }

  /// Helper to trigger a stack deploy (by stack id).
  Future<http.Response> updateStack(
      int endpointId, int stackId, Map<String, dynamic> body) async {
    return post('/api/endpoints/$endpointId/stacks/$stackId', body);
  }
}
