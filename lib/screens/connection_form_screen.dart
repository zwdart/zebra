import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ssh_connection.dart';
import '../providers/connection_provider.dart';
import '../l10n/app_localizations.dart';

class ConnectionFormScreen extends StatefulWidget {
  final SshConnection? connection;

  const ConnectionFormScreen({super.key, this.connection});

  @override
  State<ConnectionFormScreen> createState() => _ConnectionFormScreenState();
}

class _ConnectionFormScreenState extends State<ConnectionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _hostCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _passwordCtrl;
  late TextEditingController _keyPathCtrl;
  late TextEditingController _passphraseCtrl;
  late TextEditingController _remarkCtrl;
  String _authType = 'password';
  bool _obscurePassword = true;
  bool _obscurePassphrase = true;

  bool get isEditing => widget.connection != null;

  @override
  void initState() {
    super.initState();
    final conn = widget.connection;
    _nameCtrl = TextEditingController(text: conn?.name ?? '');
    _hostCtrl = TextEditingController(text: conn?.host ?? '');
    _portCtrl = TextEditingController(text: conn?.port.toString() ?? '22');
    _userCtrl = TextEditingController(text: conn?.username ?? '');
    _passwordCtrl = TextEditingController(text: conn?.password ?? '');
    _keyPathCtrl = TextEditingController(text: conn?.privateKeyPath ?? '');
    _passphraseCtrl = TextEditingController(text: conn?.passphrase ?? '');
    _remarkCtrl = TextEditingController(text: conn?.remark ?? '');
    _authType = conn?.authType ?? 'password';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passwordCtrl.dispose();
    _keyPathCtrl.dispose();
    _passphraseCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? loc.editConnection : loc.addConnection),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(loc.save, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: InputDecoration(labelText: loc.connectionName),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _hostCtrl,
              decoration: InputDecoration(labelText: loc.host),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _portCtrl,
              decoration: InputDecoration(labelText: loc.port),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                final port = int.tryParse(v);
                if (port == null || port < 1 || port > 65535) return 'Invalid port';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _userCtrl,
              decoration: InputDecoration(labelText: loc.username),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            Text(loc.authType, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'password', label: Text(loc.passwordAuth)),
                ButtonSegment(value: 'key', label: Text(loc.keyAuth)),
              ],
              selected: {_authType},
              onSelectionChanged: (v) => setState(() => _authType = v.first),
            ),
            const SizedBox(height: 16),
            if (_authType == 'password') ...[
              TextFormField(
                controller: _passwordCtrl,
                decoration: InputDecoration(
                  labelText: loc.password,
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                obscureText: _obscurePassword,
              ),
            ] else ...[
              TextFormField(
                controller: _keyPathCtrl,
                decoration: InputDecoration(
                  labelText: loc.privateKey,
                  hintText: '/home/user/.ssh/id_rsa',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.folder_open),
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles();
                      if (result != null && result.files.single.path != null) {
                        setState(() => _keyPathCtrl.text = result.files.single.path!);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passphraseCtrl,
                decoration: InputDecoration(
                  labelText: loc.passphrase,
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassphrase ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassphrase = !_obscurePassphrase),
                  ),
                ),
                obscureText: _obscurePassphrase,
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _remarkCtrl,
              decoration: InputDecoration(labelText: loc.remark),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final conn = SshConnection(
      id: widget.connection?.id,
      name: _nameCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text) ?? 22,
      username: _userCtrl.text.trim(),
      authType: _authType,
      password: _authType == 'password' ? _passwordCtrl.text : null,
      privateKeyPath: _authType == 'key' ? _keyPathCtrl.text.trim() : null,
      passphrase: _authType == 'key' ? _passphraseCtrl.text : null,
      remark: _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim(),
    );

    final provider = context.read<ConnectionProvider>();
    if (isEditing) {
      provider.updateConnection(conn);
    } else {
      provider.addConnection(conn);
    }

    Navigator.pop(context);
  }
}
