import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafev2/services/usb_sensor/device_claim.dart';

void main() {
  group('parseClaimPayload', () {
    test('reads the label link', () {
      final payload = parseClaimPayload(
        'https://isdasafe.example.com/?claim=6C383B124B00.ABCD2345EFGH',
      );
      expect(payload?.deviceId, '6C383B124B00');
      expect(payload?.code, 'ABCD2345EFGH');
    });

    test('reads a bare ID.CODE, ignoring case, dashes and spaces', () {
      final payload = parseClaimPayload(' 6c383b124b00.abcd-2345-efgh ');
      expect(payload?.deviceId, '6C383B124B00');
      expect(payload?.code, 'ABCD2345EFGH');
    });

    test('rejects other QR codes', () {
      expect(parseClaimPayload('https://example.com/menu'), isNull);
      expect(parseClaimPayload('hello'), isNull);
      expect(parseClaimPayload('https://x/?claim=NOTHEX.ABCD2345EFGH'), isNull);
      expect(parseClaimPayload('6C383B124B00.SHORT'), isNull);
    });
  });

  test('claimPayloadFrom accepts what people type off the label', () {
    final payload = claimPayloadFrom('6C38 3B12 4B00', 'abcd-2345-efgh');
    expect(payload?.deviceId, '6C383B124B00');
    expect(payload?.code, 'ABCD2345EFGH');
    expect(claimPayloadFrom('6C383B12', 'ABCD2345EFGH'), isNull);
  });

  test('PendingClaimLink hands the link out once', () {
    PendingClaimLink.captureFrom(
      Uri.parse('https://x.example/?claim=6C383B124B00.ABCD2345EFGH'),
    );
    expect(PendingClaimLink.take()?.deviceId, '6C383B124B00');
    expect(PendingClaimLink.take(), isNull);

    PendingClaimLink.captureFrom(Uri.parse('https://x.example/'));
    expect(PendingClaimLink.take(), isNull);
  });
}
