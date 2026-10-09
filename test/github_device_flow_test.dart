import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gitpush/services/github_device_flow.dart';

// Gerçek token deseni kaynakta görünmesin diye çalışma anında birleştirilir.
String _fakeToken() => ['gh', 'o_'].join() + 'a' * 36;

GitHubDeviceFlow _flow(MockClient client) => GitHubDeviceFlow(
      clientIdOverride: 'Iv1.0123456789abcdef',
      client: client,
      sleep: (_) async {},
    );

http.Response _json(Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

Map<String, dynamic> _codeResponse({String uri = 'https://github.com/login/device'}) => {
      'device_code': 'dev123',
      'user_code': 'ABCD-1234',
      'verification_uri': uri,
      'expires_in': 900,
      'interval': 5,
    };

const _info = DeviceCodeInfo(
  deviceCode: 'dev123',
  userCode: 'ABCD-1234',
  verificationUri: 'https://github.com/login/device',
  expiresIn: 900,
  interval: 5,
);

void main() {
  group('GitHubDeviceFlow', () {
    test('client id biçimi doğrulanır', () {
      expect(GitHubDeviceFlow.isValidClientId('Iv1.0123456789abcdef'), isTrue);
      expect(GitHubDeviceFlow.isValidClientId(''), isFalse);
      expect(GitHubDeviceFlow.isValidClientId('kısa id'), isFalse);
    });

    test('start kod ve adresi döndürür, scope gönderir', () async {
      late http.Request seen;
      final flow = _flow(MockClient((req) async {
        seen = req;
        return _json(_codeResponse());
      }));
      final info = await flow.start();
      expect(info.userCode, 'ABCD-1234');
      expect(seen.bodyFields['scope'], 'repo workflow');
      expect(seen.headers['Accept'], 'application/json');
    });

    test('yalnızca herkese açık kapsam gönderilebilir', () async {
      late http.Request seen;
      final flow = _flow(MockClient((req) async {
        seen = req;
        return _json(_codeResponse());
      }));
      await flow.start(scopeOverride: GitHubDeviceFlow.scopePublic);
      expect(seen.bodyFields['scope'], 'public_repo workflow');
    });

    test('izin verilmeyen kapsam ağa çıkmadan reddedilir', () async {
      var calls = 0;
      final flow = _flow(MockClient((_) async {
        calls++;
        return _json(_codeResponse());
      }));
      await expectLater(flow.start(scopeOverride: 'admin:org'), throwsA(isA<DeviceFlowException>()));
      expect(calls, 0);
    });

    test('geçersiz client id ağa çıkmadan reddedilir', () async {
      var calls = 0;
      final flow = GitHubDeviceFlow(
        clientIdOverride: '',
        client: MockClient((_) async {
          calls++;
          return _json(_codeResponse());
        }),
        sleep: (_) async {},
      );
      await expectLater(flow.start(), throwsA(isA<DeviceFlowException>()));
      expect(calls, 0);
    });

    test('github.com dışı doğrulama adresi reddedilir', () async {
      final flow = _flow(MockClient((_) async => _json(_codeResponse(uri: 'https://evil.example/login'))));
      expect(flow.start(), throwsA(isA<DeviceFlowException>()));
    });

    test('device_flow_disabled anlaşılır mesaj verir', () async {
      final flow = _flow(MockClient((_) async => _json({'error': 'device_flow_disabled'})));
      expect(
        flow.start(),
        throwsA(isA<DeviceFlowException>().having((e) => e.message, 'message', contains('Device Flow'))),
      );
    });

    test('pending sonrası token gelince döner', () async {
      final token = _fakeToken();
      var calls = 0;
      final flow = _flow(MockClient((_) async {
        calls++;
        return calls < 3 ? _json({'error': 'authorization_pending'}) : _json({'access_token': token});
      }));
      expect(await flow.pollForToken(_info), token);
      expect(calls, 3);
    });

    test('slow_down aralığı artırır, access_denied hata verir', () async {
      var calls = 0;
      final flow = _flow(MockClient((_) async {
        calls++;
        return calls == 1 ? _json({'error': 'slow_down', 'interval': 10}) : _json({'error': 'access_denied'});
      }));
      await expectLater(flow.pollForToken(_info), throwsA(isA<DeviceFlowException>()));
      expect(calls, 2);
    });

    test('iptal edilirse null döner ve ağa istek atmaz', () async {
      var calls = 0;
      final flow = _flow(MockClient((_) async {
        calls++;
        return _json({'error': 'authorization_pending'});
      }));
      expect(await flow.pollForToken(_info, isCancelled: () => true), isNull);
      expect(calls, 0);
    });

    test('süre dolarsa hata verir', () async {
      final flow = _flow(MockClient((_) async => _json({'error': 'authorization_pending'})));
      const info = DeviceCodeInfo(
        deviceCode: 'd',
        userCode: 'U',
        verificationUri: 'https://github.com/login/device',
        expiresIn: 10,
        interval: 5,
      );
      await expectLater(flow.pollForToken(info), throwsA(isA<DeviceFlowException>()));
    });
  });
}
