import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isdasafev2/widgets/google_logo.dart';

void main() {
  testWidgets('the Google logo draws as the four-colour G', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: GoogleLogo(size: 24))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(tester.getSize(find.byType(GoogleLogo)), const Size(24, 24));
    expect(tester.takeException(), isNull);
  });
}
