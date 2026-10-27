import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'app_language.dart';

const _canvas = Color(0xFFF6F8F6);
const _ink = Color(0xFF17231F);
const _muted = Color(0xFF7B8983);
const _relayGreen = Color(0xFF176B55);
const _relayMint = Color(0xFFE6F4ED);

class StorageDataScreen extends StatefulWidget {
  const StorageDataScreen({super.key});

  @override
  State<StorageDataScreen> createState() => _StorageDataScreenState();
}

class _StorageDataScreenState extends State<StorageDataScreen> {
  Map<String, int> usage = const {'sentBytes': 0, 'receivedBytes': 0, 'requestCount': 0};
  bool loading = true;
  bool resetting = false;
  bool dataSaver = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final latestUsage = await Api.trafficUsage();
      if (!mounted) return;
      setState(() {
        usage = latestUsage;
        dataSaver = prefs.getBool('data_saver_enabled') ?? false;
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _setDataSaver(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('data_saver_enabled', value);
      if (mounted) setState(() => dataSaver = value);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'preference_save_failed'))),
      );
    }
  }

  Future<void> _clearMemoryCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(context, 'clear_cache_confirm')),
        content: Text(tr(context, 'clear_cache_description')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr(context, 'cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(tr(context, 'clear_cache'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'cache_cleared'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'cache_clear_failed'))),
        );
      }
    }
  }

  Future<void> _resetUsage() async {
    if (resetting) return;
    setState(() => resetting = true);
    await Api.resetTrafficUsage();
    await _load();
    if (mounted) setState(() => resetting = false);
  }

  Future<String?> _askPassphrase({required bool confirm}) async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: Text(confirm ? tr(context, 'create_backup') : tr(context, 'restore_backup')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr(context, 'backup_passphrase_note')),
          const SizedBox(height: 12),
          TextField(controller: controller, obscureText: true, autofocus: true, decoration: InputDecoration(labelText: tr(context, 'backup_passphrase'), border: const OutlineInputBorder())),
          if (confirm) ...[
            const SizedBox(height: 10),
            TextField(controller: confirmController, obscureText: true, decoration: InputDecoration(labelText: tr(context, 'confirm_passphrase'), border: const OutlineInputBorder())),
          ],
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.red))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr(context, 'cancel'))),
          FilledButton(onPressed: () {
            final value = controller.text;
            if (value.trim().length < 10) {
              setDialogState(() => error = tr(context, 'backup_passphrase_short'));
              return;
            }
            if (confirm && value != confirmController.text) {
              setDialogState(() => error = tr(context, 'backup_passphrase_mismatch'));
              return;
            }
            Navigator.pop(dialogContext, value);
          }, child: Text(tr(context, 'continue'))),
        ],
      )),
    );
    controller.dispose();
    confirmController.dispose();
    return result;
  }

  Future<void> _createBackup() async {
    final saveDialogTitle = tr(context, 'save_backup');
    final backupCreatedLabel = tr(context, 'backup_created');
    final backupFailedLabel = tr(context, 'backup_failed');
    final passphrase = await _askPassphrase(confirm: true);
    if (passphrase == null || !mounted) return;
    try {
      final bytes = await BackupService.createBackup(passphrase);
      final now = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-').split('.').first;
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: saveDialogTitle,
        fileName: 'veyra-backup-$now.veyra',
        type: FileType.custom,
        allowedExtensions: const ['veyra'],
        bytes: bytes,
      );
      if (!mounted) return;
      if (saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(backupCreatedLabel)));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$backupFailedLabel: ${error.toString().replaceFirst('Exception: ', '')}')));
    }
  }

  Future<void> _restoreBackup() async {
    final restoreTitle = tr(context, 'restore_backup');
    final restoreWarning = tr(context, 'restore_backup_warning');
    final cancelLabel = tr(context, 'cancel');
    final chooseBackupTitle = tr(context, 'choose_backup');
    final restoredMessage = tr(context, 'backup_restored');
    final restoreFailedLabel = tr(context, 'restore_failed');
    final confirmation = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(restoreTitle),
        content: Text(restoreWarning),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(cancelLabel)),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(restoreTitle)),
        ],
      ),
    );
    if (confirmation != true || !mounted) return;
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: chooseBackupTitle,
      type: FileType.custom,
      allowedExtensions: const ['veyra'],
      withData: true,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty || picked.files.single.bytes == null || !mounted) return;
    final passphrase = await _askPassphrase(confirm: false);
    if (passphrase == null || !mounted) return;
    try {
      await BackupService.restoreBackup(picked.files.single.bytes!, passphrase);
      await loadSavedLocale();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(restoredMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$restoreFailedLabel: ${error.toString().replaceFirst('Exception: ', '')}')));
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _canvas,
        appBar: AppBar(title: Text(tr(context, 'storage'))),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: _relayGreen, borderRadius: BorderRadius.circular(22)),
              child: Row(children: [
                const Icon(Icons.storage_rounded, color: Colors.white, size: 34),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(context, 'storage'), style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(tr(context, 'storage_intro'), style: const TextStyle(color: Color(0xFFD8EEE5), height: 1.4)),
                ])),
              ]),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: tr(context, 'network_usage'),
              subtitle: tr(context, 'network_usage_note'),
              child: loading
                  ? const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
                  : Column(children: [
                      _usageRow(tr(context, 'data_sent'), _formatBytes(usage['sentBytes'] ?? 0), Icons.north_east_rounded),
                      _usageRow(tr(context, 'data_received'), _formatBytes(usage['receivedBytes'] ?? 0), Icons.south_west_rounded),
                      _usageRow(tr(context, 'api_requests'), '${usage['requestCount'] ?? 0}', Icons.swap_vert_rounded),
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: TextButton.icon(
                        onPressed: resetting ? null : _resetUsage,
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: Text(resetting ? tr(context, 'resetting') : tr(context, 'reset_counters')),
                      )),
                    ]),
            ),
            const SizedBox(height: 10),
            _sectionCard(
              title: tr(context, 'backup_restore'),
              subtitle: tr(context, 'backup_restore_note'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilledButton.icon(onPressed: loading ? null : _createBackup, icon: const Icon(Icons.backup_outlined), label: Text(tr(context, 'create_backup'))),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: loading ? null : _restoreBackup, icon: const Icon(Icons.settings_backup_restore_rounded), label: Text(tr(context, 'restore_backup'))),
                const SizedBox(height: 8),
                Text(tr(context, 'backup_security_note'), style: const TextStyle(color: _muted, fontSize: 12, height: 1.4)),
              ]),
            ),
            const SizedBox(height: 10),
            _sectionCard(
              title: tr(context, 'image_cache'),
              subtitle: tr(context, 'image_cache_note'),
              child: Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
                onPressed: _clearMemoryCache,
                icon: const Icon(Icons.cleaning_services_outlined),
                label: Text(tr(context, 'clear_image_cache')),
              )),
            ),
            const SizedBox(height: 10),
            _sectionCard(
              title: tr(context, 'data_saver'),
              subtitle: tr(context, 'data_saver_note'),
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: dataSaver,
                onChanged: _setDataSaver,
                activeThumbColor: _relayGreen,
                title: Text(tr(context, 'enable_data_saver'), style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
                subtitle: Text(tr(context, 'preference_saved'), style: const TextStyle(color: _muted, fontSize: 12)),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: _relayMint, borderRadius: BorderRadius.circular(16)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded, color: _relayGreen),
                const SizedBox(width: 10),
                Expanded(child: Text(tr(context, 'storage_notice'), style: const TextStyle(color: _ink, height: 1.4, fontSize: 12))),
              ]),
            ),
          ],
        ),
      );

  Widget _sectionCard({required String title, required String subtitle, required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: _muted, height: 1.45, fontSize: 12)),
          const SizedBox(height: 10),
          child,
        ]),
      );

  Widget _usageRow(String label, String value, IconData icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, size: 19, color: _relayGreen),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(color: _ink))),
          Text(value, style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
        ]),
      );
}
