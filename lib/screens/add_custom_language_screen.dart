import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/language.dart';
import '../services/language_install_service.dart';
import '../services/language_service.dart';

class AddCustomLanguageScreen extends StatefulWidget {
  const AddCustomLanguageScreen({super.key});

  @override
  State<AddCustomLanguageScreen> createState() => _AddCustomLanguageScreenState();
}

class _AddCustomLanguageScreenState extends State<AddCustomLanguageScreen> {
  final _formKey = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _version = TextEditingController();
  final _url = TextEditingController();
  final _registry = TextEditingController();
  final _command = TextEditingController(text: './bin/main %file%');
  final _libManager = TextEditingController();

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _version.dispose();
    _url.dispose();
    _registry.dispose();
    _command.dispose();
    _libManager.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final lang = Language(
      id: _id.text.trim(),
      name: _name.text.trim(),
      version: _version.text.trim(),
      url: _url.text.trim(),
      libManager: _libManager.text.trim().isEmpty ? null : _libManager.text.trim(),
      registry: _registry.text.trim().isEmpty ? null : _registry.text.trim(),
      launchCommand: _command.text.trim(),
      builtin: false,
    );
    await LanguageInstallService.instance.addCustom(lang);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = LanguageService.of(context);
    return Scaffold(
      backgroundColor: VscodeTheme.bg,
      appBar: AppBar(
        title: Text(l10n.tr('languages.add_custom')),
        backgroundColor: VscodeTheme.bgSidebar,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(_id, l10n.tr('languages.field.id'), required: true,
                hint: 'crystal',
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return l10n.tr('languages.field.required');
                  if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(t)) {
                    return l10n.tr('languages.field.id_format');
                  }
                  return null;
                }),
            _field(_name, l10n.tr('languages.field.name'),
                required: true, hint: 'Crystal'),
            _field(_version, l10n.tr('languages.field.version'),
                required: true, hint: '1.12.0'),
            _field(_url, l10n.tr('languages.field.url'),
                required: true,
                hint: 'https://github.com/.../crystal-1.12.0-linux-aarch64.tar.gz',
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return l10n.tr('languages.field.required');
                  if (!t.startsWith('http')) return l10n.tr('languages.field.url_format');
                  return null;
                }),
            _field(_libManager, l10n.tr('languages.field.lib_manager'),
                hint: 'pip / npm / cargo / gem'),
            _field(_registry, l10n.tr('languages.field.registry'),
                hint: 'https://...'),
            _field(_command, l10n.tr('languages.field.launch_command'),
                hint: './bin/crystal run %file%'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: VscodeTheme.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
              ),
              child: Text(l10n.tr('languages.save')),
            ),
            const SizedBox(height: 12),
            Text(l10n.tr('languages.add_custom_hint'),
                style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {String? hint,
      bool required = false,
      String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        autocorrect: false,
        style: const TextStyle(color: VscodeTheme.fg, fontSize: 13),
        decoration: InputDecoration(
          labelText: label + (required ? ' *' : ''),
          hintText: hint,
          labelStyle: const TextStyle(color: VscodeTheme.fgLabel, fontSize: 12),
          hintStyle: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 12),
          filled: true,
          fillColor: VscodeTheme.bgSidebar,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: VscodeTheme.border),
          ),
        ),
        validator: validator ??
            (required
                ? (v) => (v == null || v.trim().isEmpty)
                    ? LanguageService.of(context, listen: false)
                        .tr('languages.field.required')
                    : null
                : null),
      ),
    );
  }
}
