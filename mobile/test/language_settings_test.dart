import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veyra_messenger/app_language.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appLocale.value = null;
  });

  testWidgets('language screen offers English, Marathi, Hindi and system default',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      supportedLocales: [Locale('en'), Locale('mr'), Locale('hi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: LanguageSettingsScreen(),
    ));

    expect(find.text('App language'), findsOneWidget);
    expect(find.text('English'), findsWidgets);
    expect(find.text('मराठी (Marathi)'), findsOneWidget);
    expect(find.text('हिन्दी (Hindi)'), findsOneWidget);
    expect(find.text('System default'), findsOneWidget);
  });

  testWidgets('selecting Marathi persists the preference',
      (WidgetTester tester) async {
    await tester.pumpWidget(ValueListenableBuilder<Locale?>(
      valueListenable: appLocale,
      builder: (context, locale, _) => MaterialApp(
        locale: locale ?? const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('mr'), Locale('hi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const LanguageSettingsScreen(),
      ),
    ));

    final marathiOption = find.text('मराठी (Marathi)');
    await tester.ensureVisible(marathiOption);
    await tester.pumpAndSettle();
    await tester.tap(marathiOption);
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('app_language'), 'mr');
    expect(appLocale.value, const Locale('mr'));
  });
}
