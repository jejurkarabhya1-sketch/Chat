import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Null means use the operating system language when it is supported.
final ValueNotifier<Locale?> appLocale = ValueNotifier<Locale?>(null);

Future<void> loadSavedLocale() async {
  try {
    final preferences = await SharedPreferences.getInstance();
    final languageCode = preferences.getString('app_language');
    appLocale.value = languageCode == null || languageCode == 'system'
        ? null
        : Locale(languageCode);
  } catch (_) {
    // Language settings are optional; do not block startup if storage fails.
    appLocale.value = null;
  }
}

String tr(BuildContext context, String key) {
  final languageCode = Localizations.localeOf(context).languageCode;
  return _strings[languageCode]?[key] ?? _strings['en']![key] ?? key;
}

const Map<String, Map<String, String>> _strings = {
  'en': {
    'chats': 'Chats', 'updates': 'Updates', 'calls': 'Calls', 'settings': 'Settings',
    'settings_subtitle': 'Make Veyra feel right for you.', 'account': 'Your Veyra account',
    'account_subtitle': 'Phone verification enabled in development',
    'privacy': 'Privacy and security', 'privacy_subtitle': 'Encryption review is a release requirement',
    'notifications': 'Notifications', 'notifications_subtitle': 'Push notifications planned',
    'help': 'Help and feedback', 'help_subtitle': 'Share feedback as we build',
    'language': 'Language', 'language_subtitle': 'Choose the language used in Veyra',
    'storage': 'Storage and data', 'storage_subtitle': 'Manage storage and data usage',
    'backup_restore': 'Backup and restore', 'backup_restore_note': 'Create a password-protected backup of cached chats and preferences, or restore one.', 'create_backup': 'Create encrypted backup', 'restore_backup': 'Restore backup', 'backup_security_note': 'Backups are encrypted with your passphrase. Keep it safe: it cannot be recovered. Includes local cached messages only, not full server history, login tokens, or private keys.', 'backup_passphrase': 'Backup passphrase', 'confirm_passphrase': 'Confirm passphrase', 'backup_passphrase_note': 'Use at least 10 characters. You will need this passphrase to restore the backup.', 'backup_passphrase_short': 'Use at least 10 characters.', 'backup_passphrase_mismatch': 'Passphrases do not match.', 'continue': 'Continue', 'save_backup': 'Save Veyra backup', 'backup_created': 'Encrypted backup created.', 'backup_failed': 'Backup failed', 'restore_backup_warning': 'Restoring replaces the local cached chat data on this device. It does not change server messages. Continue?', 'choose_backup': 'Choose Veyra backup', 'backup_restored': 'Backup restored. The inbox will sync with the server on the next refresh.', 'restore_failed': 'Restore failed',
    'storage_intro': 'Review estimated API data use and manage temporary memory cache.', 'network_usage': 'Network usage', 'network_usage_note': 'Approximate API payload totals on this device. HTTP headers, TLS overhead, and WebSocket traffic are not included.', 'data_sent': 'Data sent', 'data_received': 'Data received', 'api_requests': 'API requests', 'reset_counters': 'Reset counters', 'resetting': 'Resetting…', 'image_cache': 'Temporary image cache', 'image_cache_note': 'Clears Flutter’s in-memory image cache only. This does not remove messages, login details, or language preferences.', 'clear_image_cache': 'Clear image cache', 'data_saver': 'Data saver', 'data_saver_note': 'Save your preference for future media-transfer features. Media auto-download is not implemented in this build, so this setting does not currently change media behavior.', 'enable_data_saver': 'Enable data saver', 'preference_saved': 'Preference saved on this device', 'storage_notice': 'Veyra does not yet download or store chat media locally. These controls do not delete messages or server data.', 'clear_cache_confirm': 'Clear temporary image cache?', 'clear_cache_description': 'This clears images currently held in Flutter memory. It does not delete chats, account data, or files on your device.', 'cancel': 'Cancel', 'clear_cache': 'Clear cache', 'cache_cleared': 'Temporary image cache cleared.', 'cache_clear_failed': 'Could not clear the image cache.', 'preference_save_failed': 'Could not save this preference. Please try again.',
    'sign_out': 'Sign out', 'language_title': 'App language',
    'language_description': 'Choose how Veyra appears on this device.',
    'system_default': 'System default', 'english': 'English', 'marathi': 'मराठी (Marathi)',
    'hindi': 'हिन्दी (Hindi)', 'language_saved': 'App language updated',
    'system_description': 'Use your device language when supported',
    'language_note': 'Your choice is saved on this device and applies on Web and Android.',
    'chat_subtitle': 'Your people, one place.', 'updates_subtitle': 'Little moments from your circle.',
    'updates_empty_title': 'Updates are coming soon', 'updates_empty_body': 'We’re shaping a thoughtful space for temporary photos, notes and status updates.',
    'calls_subtitle': 'Connect when a message is not enough.', 'calls_title': 'Voice and video calls',
    'calls_body': 'Calling will be added after the real-time messaging and security foundations are verified.',
    'banner_title': 'Make room for\nmeaningful moments.', 'banner_subtitle': 'Simple chats. Thoughtful design.', 'messages': 'Messages', 'search_chats': 'Search conversations',
  },
  'mr': {
    'chats': 'चॅट्स', 'updates': 'अपडेट्स', 'calls': 'कॉल्स', 'settings': 'सेटिंग्ज',
    'settings_subtitle': 'Veyra तुमच्या पसंतीनुसार बदला.', 'account': 'तुमचे Veyra खाते',
    'account_subtitle': 'विकास आवृत्तीत फोन पडताळणी सुरू आहे',
    'privacy': 'गोपनीयता आणि सुरक्षा', 'privacy_subtitle': 'एन्क्रिप्शनची तपासणी रिलीजपूर्वी आवश्यक आहे',
    'notifications': 'सूचना', 'notifications_subtitle': 'पुश सूचना लवकरच उपलब्ध होतील',
    'help': 'मदत आणि अभिप्राय', 'help_subtitle': 'अॅप तयार होत असताना अभिप्राय द्या',
    'language': 'भाषा', 'language_subtitle': 'Veyra मध्ये वापरली जाणारी भाषा निवडा',
    'storage': 'स्टोरेज आणि डेटा', 'storage_subtitle': 'स्टोरेज आणि डेटा वापर व्यवस्थापित करा',
    'backup_restore': 'बॅकअप आणि पुनर्संचयित करा', 'backup_restore_note': 'कॅश केलेल्या चॅट्स आणि पसंतींचा पासवर्ड-संरक्षित बॅकअप तयार करा किंवा पुनर्संचयित करा.', 'create_backup': 'एन्क्रिप्टेड बॅकअप तयार करा', 'restore_backup': 'बॅकअप पुनर्संचयित करा', 'backup_security_note': 'बॅकअप तुमच्या पासफ्रेजने एन्क्रिप्ट केला जातो. तो सुरक्षित ठेवा; तो परत मिळवता येत नाही. यात स्थानिक कॅश केलेले संदेश असतात; संपूर्ण सर्व्हर इतिहास, लॉगिन टोकन किंवा खाजगी की नसतात.', 'backup_passphrase': 'बॅकअप पासफ्रेज', 'confirm_passphrase': 'पासफ्रेजची पुष्टी करा', 'backup_passphrase_note': 'किमान १० अक्षरे वापरा. बॅकअप पुनर्संचयित करण्यासाठी हा पासफ्रेज लागेल.', 'backup_passphrase_short': 'किमान १० अक्षरे वापरा.', 'backup_passphrase_mismatch': 'पासफ्रेज जुळत नाहीत.', 'continue': 'पुढे जा', 'save_backup': 'Veyra बॅकअप जतन करा', 'backup_created': 'एन्क्रिप्टेड बॅकअप तयार झाला.', 'backup_failed': 'बॅकअप अयशस्वी', 'restore_backup_warning': 'पुनर्संचयित केल्याने या डिव्हाइसवरील स्थानिक कॅश केलेला चॅट डेटा बदलला जाईल. सर्व्हरवरील संदेश बदलणार नाहीत. पुढे जायचे?', 'choose_backup': 'Veyra बॅकअप निवडा', 'backup_restored': 'बॅकअप पुनर्संचयित झाला. पुढील रिफ्रेशमध्ये इनबॉक्स सर्व्हरशी सिंक होईल.', 'restore_failed': 'पुनर्संचयित करणे अयशस्वी',
    'storage_intro': 'अंदाजे API डेटा वापर पाहा आणि तात्पुरती मेमरी कॅशे व्यवस्थापित करा.', 'network_usage': 'नेटवर्क वापर', 'network_usage_note': 'या डिव्हाइसवरील API डेटा वापराचा अंदाज. HTTP हेडर, TLS आणि WebSocket डेटा यात समाविष्ट नाही.', 'data_sent': 'पाठवलेला डेटा', 'data_received': 'मिळालेला डेटा', 'api_requests': 'API विनंत्या', 'reset_counters': 'काउंटर रीसेट करा', 'resetting': 'रीसेट होत आहे…', 'image_cache': 'तात्पुरती इमेज कॅशे', 'image_cache_note': 'फक्त Flutter मधील मेमरी इमेज कॅशे साफ होते. संदेश, लॉगिन किंवा भाषा सेटिंग्ज हटत नाहीत.', 'clear_image_cache': 'इमेज कॅशे साफ करा', 'data_saver': 'डेटा सेव्हर', 'data_saver_note': 'भविष्यातील मीडिया ट्रान्सफर सुविधांसाठी ही पसंती जतन करा. या आवृत्तीत मीडिया ऑटो-डाउनलोड उपलब्ध नसल्याने सध्या वर्तन बदलत नाही.', 'enable_data_saver': 'डेटा सेव्हर सुरू करा', 'preference_saved': 'पसंती या डिव्हाइसवर जतन केली', 'storage_notice': 'Veyra सध्या चॅट मीडिया स्थानिकरित्या डाउनलोड किंवा साठवत नाही. हे पर्याय संदेश किंवा सर्व्हरवरील डेटा हटवत नाहीत.', 'clear_cache_confirm': 'तात्पुरती इमेज कॅशे साफ करायची?', 'clear_cache_description': 'Flutter मेमरीतील प्रतिमा साफ होतील. चॅट, खाते माहिती किंवा डिव्हाइसवरील फाइल्स हटणार नाहीत.', 'cancel': 'रद्द करा', 'clear_cache': 'कॅशे साफ करा', 'cache_cleared': 'तात्पुरती इमेज कॅशे साफ केली.', 'cache_clear_failed': 'इमेज कॅशे साफ करता आली नाही.', 'preference_save_failed': 'पसंती जतन करता आली नाही. पुन्हा प्रयत्न करा.',
    'sign_out': 'साइन आउट', 'language_title': 'अॅपची भाषा',
    'language_description': 'या डिव्हाइसवर Veyra कोणत्या भाषेत दिसावे ते निवडा.',
    'system_default': 'डिव्हाइसची भाषा', 'english': 'English (इंग्रजी)', 'marathi': 'मराठी',
    'hindi': 'हिन्दी (हिंदी)', 'language_saved': 'अॅपची भाषा बदलली',
    'system_description': 'समर्थित असल्यास डिव्हाइसची भाषा वापरा',
    'language_note': 'तुमची निवड या डिव्हाइसवर जतन केली जाईल आणि Web व Android वर लागू होईल.',
    'chat_subtitle': 'तुमची माणसं, एकाच ठिकाणी.', 'updates_subtitle': 'तुमच्या जवळच्या लोकांचे छोटे क्षण.',
    'updates_empty_title': 'अपडेट्स लवकरच येतील', 'updates_empty_body': 'फोटो, छोट्या नोंदी आणि स्टेटस शेअर करण्यासाठी आम्ही जागा तयार करत आहोत.',
    'calls_subtitle': 'मेसेज पुरेसा नसेल तेव्हा संपर्कात राहा.', 'calls_title': 'व्हॉइस आणि व्हिडिओ कॉल',
    'calls_body': 'रिअल-टाइम मेसेजिंग आणि सुरक्षा तपासल्यानंतर कॉलिंग जोडले जाईल.',
    'banner_title': 'अर्थपूर्ण क्षणांसाठी जागा ठेवा.', 'banner_subtitle': 'सोपे चॅट्स. विचारपूर्वक डिझाइन.', 'messages': 'संदेश', 'search_chats': 'संभाषणे शोधा',
  },
  'hi': {
    'chats': 'चैट', 'updates': 'अपडेट', 'calls': 'कॉल', 'settings': 'सेटिंग्स',
    'settings_subtitle': 'Veyra को अपनी पसंद के अनुसार बनाएं।', 'account': 'आपका Veyra खाता',
    'account_subtitle': 'डेवलपमेंट में फ़ोन सत्यापन सक्षम है',
    'privacy': 'गोपनीयता और सुरक्षा', 'privacy_subtitle': 'रिलीज़ से पहले एन्क्रिप्शन की समीक्षा आवश्यक है',
    'notifications': 'सूचनाएं', 'notifications_subtitle': 'पुश सूचनाएं जल्द उपलब्ध होंगी',
    'help': 'सहायता और प्रतिक्रिया', 'help_subtitle': 'निर्माण के दौरान अपनी प्रतिक्रिया दें',
    'language': 'भाषा', 'language_subtitle': 'Veyra में इस्तेमाल होने वाली भाषा चुनें',
    'storage': 'स्टोरेज और डेटा', 'storage_subtitle': 'स्टोरेज और डेटा उपयोग प्रबंधित करें',
    'backup_restore': 'बैकअप और रीस्टोर', 'backup_restore_note': 'कैश की गई चैट और प्राथमिकताओं का पासवर्ड-सुरक्षित बैकअप बनाएं या रीस्टोर करें।', 'create_backup': 'एन्क्रिप्टेड बैकअप बनाएं', 'restore_backup': 'बैकअप रीस्टोर करें', 'backup_security_note': 'बैकअप आपके पासफ़्रेज़ से एन्क्रिप्ट होता है। इसे सुरक्षित रखें; इसे वापस नहीं पाया जा सकता। इसमें केवल स्थानीय कैश किए गए संदेश हैं, पूरा सर्वर इतिहास, लॉगिन टोकन या निजी कुंजियां नहीं।', 'backup_passphrase': 'बैकअप पासफ़्रेज़', 'confirm_passphrase': 'पासफ़्रेज़ की पुष्टि करें', 'backup_passphrase_note': 'कम से कम 10 अक्षर इस्तेमाल करें। बैकअप रीस्टोर करने के लिए यह पासफ़्रेज़ चाहिए।', 'backup_passphrase_short': 'कम से कम 10 अक्षर इस्तेमाल करें।', 'backup_passphrase_mismatch': 'पासफ़्रेज़ मेल नहीं खाते।', 'continue': 'जारी रखें', 'save_backup': 'Veyra बैकअप सेव करें', 'backup_created': 'एन्क्रिप्टेड बैकअप बन गया।', 'backup_failed': 'बैकअप विफल', 'restore_backup_warning': 'रीस्टोर करने से इस डिवाइस का स्थानीय कैश चैट डेटा बदल जाएगा। सर्वर के संदेश नहीं बदलेंगे। जारी रखें?', 'choose_backup': 'Veyra बैकअप चुनें', 'backup_restored': 'बैकअप रीस्टोर हो गया। अगली बार रिफ्रेश होने पर इनबॉक्स सर्वर से सिंक होगा।', 'restore_failed': 'रीस्टोर विफल',
    'storage_intro': 'अनुमानित API डेटा उपयोग देखें और अस्थायी मेमोरी कैश प्रबंधित करें।', 'network_usage': 'नेटवर्क उपयोग', 'network_usage_note': 'इस डिवाइस पर अनुमानित API डेटा उपयोग। HTTP हेडर, TLS और WebSocket ट्रैफ़िक शामिल नहीं हैं।', 'data_sent': 'भेजा गया डेटा', 'data_received': 'प्राप्त डेटा', 'api_requests': 'API अनुरोध', 'reset_counters': 'काउंटर रीसेट करें', 'resetting': 'रीसेट हो रहा है…', 'image_cache': 'अस्थायी इमेज कैश', 'image_cache_note': 'केवल Flutter की मेमोरी में मौजूद इमेज कैश साफ़ करता है। संदेश, लॉगिन या भाषा सेटिंग नहीं हटती।', 'clear_image_cache': 'इमेज कैश साफ़ करें', 'data_saver': 'डेटा सेवर', 'data_saver_note': 'भविष्य की मीडिया ट्रांसफ़र सुविधाओं के लिए अपनी पसंद सहेजें। इस बिल्ड में मीडिया ऑटो-डाउनलोड उपलब्ध नहीं है, इसलिए यह सेटिंग अभी व्यवहार नहीं बदलती।', 'enable_data_saver': 'डेटा सेवर चालू करें', 'preference_saved': 'पसंद इस डिवाइस पर सहेजी गई', 'storage_notice': 'Veyra अभी चैट मीडिया को स्थानीय रूप से डाउनलोड या संग्रहीत नहीं करता। ये नियंत्रण संदेश या सर्वर डेटा नहीं हटाते।', 'clear_cache_confirm': 'अस्थायी इमेज कैश साफ़ करें?', 'clear_cache_description': 'Flutter मेमोरी में मौजूद इमेज साफ़ होंगी। चैट, खाता डेटा या डिवाइस की फ़ाइलें नहीं हटेंगी।', 'cancel': 'रद्द करें', 'clear_cache': 'कैश साफ़ करें', 'cache_cleared': 'अस्थायी इमेज कैश साफ़ किया गया।', 'cache_clear_failed': 'इमेज कैश साफ़ नहीं हो सका।', 'preference_save_failed': 'पसंद सहेजी नहीं जा सकी। कृपया फिर कोशिश करें.',
    'sign_out': 'साइन आउट', 'language_title': 'ऐप की भाषा',
    'language_description': 'इस डिवाइस पर Veyra की भाषा चुनें।',
    'system_default': 'सिस्टम की भाषा', 'english': 'English (अंग्रेज़ी)', 'marathi': 'मराठी (मराठी)',
    'hindi': 'हिन्दी', 'language_saved': 'ऐप की भाषा अपडेट हो गई',
    'system_description': 'समर्थित होने पर डिवाइस की भाषा इस्तेमाल करें',
    'language_note': 'आपकी पसंद इस डिवाइस पर सेव होगी और Web व Android पर लागू होगी।',
    'chat_subtitle': 'आपके अपने, एक ही जगह।', 'updates_subtitle': 'अपने लोगों के छोटे-छोटे पल।',
    'updates_empty_title': 'अपडेट जल्द आ रहे हैं', 'updates_empty_body': 'हम अस्थायी फ़ोटो, नोट्स और स्टेटस के लिए एक बेहतर जगह बना रहे हैं।',
    'calls_subtitle': 'जब संदेश काफ़ी न हो, तब जुड़ें।', 'calls_title': 'वॉइस और वीडियो कॉल',
    'calls_body': 'रीयल-टाइम मैसेजिंग और सुरक्षा की पुष्टि के बाद कॉलिंग जोड़ी जाएगी।',
    'banner_title': 'खास पलों के लिए जगह बनाएं।', 'banner_subtitle': 'आसान चैट। सोच-समझकर डिज़ाइन।', 'messages': 'संदेश', 'search_chats': 'बातचीत खोजें',
  },
};

class LanguageSettingsScreen extends StatefulWidget {
  const LanguageSettingsScreen({super.key});

  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  String selectedCode = appLocale.value?.languageCode ?? 'system';
  bool saving = false;

  Future<void> _selectLanguage(String code) async {
    if (saving || selectedCode == code) return;
    setState(() {
      selectedCode = code;
      saving = true;
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      if (code == 'system') {
        await preferences.remove('app_language');
        appLocale.value = null;
      } else {
        await preferences.setString('app_language', code);
        appLocale.value = Locale(code);
      }
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'language_saved'))),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        selectedCode = appLocale.value?.languageCode ?? 'system';
        saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save language preference. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr(context, 'language_title'))),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF176B55), borderRadius: BorderRadius.circular(22)),
              child: Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.translate_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(context, 'language'), style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(tr(context, 'language_description'), style: const TextStyle(color: Color(0xFFD8EEE5), height: 1.4)),
                ])),
              ]),
            ),
            const SizedBox(height: 20),
            Text(tr(context, 'language_title').toUpperCase(), style: const TextStyle(color: Color(0xFF7B8983), fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: RadioGroup<String>(
                groupValue: selectedCode,
                onChanged: (value) {
                  if (value != null) _selectLanguage(value);
                },
                child: Column(children: [
                _LanguageOption(code: 'system', title: tr(context, 'system_default'), subtitle: tr(context, 'system_description')),
                const Divider(height: 1, indent: 18, endIndent: 18),
                _LanguageOption(code: 'en', title: tr(context, 'english'), subtitle: 'English'),
                const Divider(height: 1, indent: 18, endIndent: 18),
                _LanguageOption(code: 'mr', title: tr(context, 'marathi'), subtitle: 'मराठी'),
                const Divider(height: 1, indent: 18, endIndent: 18),
                _LanguageOption(code: 'hi', title: tr(context, 'hindi'), subtitle: 'हिन्दी'),
              ])),
            ),
            if (saving) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator(color: Color(0xFF176B55))),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFE6F4ED), borderRadius: BorderRadius.circular(16)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFF176B55)),
                const SizedBox(width: 10),
                Expanded(child: Text(tr(context, 'language_note'), style: const TextStyle(color: Color(0xFF17231F), fontSize: 12, height: 1.45))),
              ]),
            ),
          ],
        ),
      );
}

class _LanguageOption extends StatelessWidget {
  final String code;
  final String title;
  final String subtitle;
  const _LanguageOption({required this.code, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => RadioListTile<String>(
        value: code,
        activeColor: const Color(0xFF176B55),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(title, style: const TextStyle(color: Color(0xFF17231F), fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(color: Color(0xFF7B8983), fontSize: 12)),
      );
}
