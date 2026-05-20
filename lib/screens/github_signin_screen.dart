import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme.dart';
import '../models/github_user.dart';
import '../services/github_oauth_service.dart';

/// Drives GitHub Device Flow end-to-end. Flow:
///  1. Hit `start` → render the user_code prominently with a "Copy" button.
///  2. User taps "Open GitHub" → external browser to verification_uri.
///  3. We poll in the background; when token arrives, pop with the user.
class GithubSignInScreen extends StatefulWidget {
  const GithubSignInScreen({super.key});

  @override
  State<GithubSignInScreen> createState() => _GithubSignInScreenState();
}

class _GithubSignInScreenState extends State<GithubSignInScreen> {
  DeviceFlowStart? _start;
  String _statusText = 'Requesting device code…';
  bool _busy = true;
  StreamSubscription<DeviceFlowStatus>? _pollSub;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    setState(() {
      _busy = true;
      _statusText = 'Requesting device code…';
    });
    try {
      final s = await GithubOAuthService.startDeviceFlow();
      if (!mounted) return;
      setState(() {
        _start = s;
        _busy = false;
        _statusText = 'Waiting for you to enter the code on github.com…';
      });
      _startPolling(s);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusText = 'Failed to start sign-in: $e';
      });
    }
  }

  void _startPolling(DeviceFlowStart s) {
    _pollSub?.cancel();
    _pollSub = GithubOAuthService.pollForToken(s).listen((status) {
      if (!mounted) return;
      switch (status.state) {
        case DeviceFlowState.pending:
          setState(() => _statusText = 'Waiting for authorization…');
          break;
        case DeviceFlowState.success:
          Navigator.pop<GithubUser?>(context, status.user);
          break;
        case DeviceFlowState.error:
          setState(() => _statusText = status.error ?? 'Unknown error');
          break;
      }
    });
  }

  @override
  void dispose() {
    _pollSub?.cancel();
    super.dispose();
  }

  Future<void> _openVerificationUri() async {
    final s = _start;
    if (s == null) return;
    final uri = Uri.parse(s.verificationUri);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _copyCode() async {
    final s = _start;
    if (s == null) return;
    await Clipboard.setData(ClipboardData(text: s.userCode));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Code copied'),
          backgroundColor: VscodeTheme.accent,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _start;
    return Scaffold(
      backgroundColor: VscodeTheme.bg,
      appBar: AppBar(
        title: const Text('Sign in with GitHub'),
        backgroundColor: VscodeTheme.bgSidebar,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _busy
            ? const Center(
                child: CircularProgressIndicator(color: VscodeTheme.accent))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline, size: 48, color: VscodeTheme.accent),
                  const SizedBox(height: 16),
                  const Text(
                    'Step 1 — Open GitHub',
                    style: TextStyle(color: VscodeTheme.fg, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  if (s != null) Text(s.verificationUri,
                    style: const TextStyle(color: VscodeTheme.accent, fontSize: 12)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: s == null ? null : _openVerificationUri,
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('Open GitHub'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VscodeTheme.accent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Step 2 — Enter this code',
                    style: TextStyle(color: VscodeTheme.fg, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: VscodeTheme.bgInput,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: VscodeTheme.border),
                    ),
                    child: Center(
                      child: SelectableText(
                        s?.userCode ?? '----',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 26,
                          letterSpacing: 4,
                          color: VscodeTheme.fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: s == null ? null : _copyCode,
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copy code'),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: VscodeTheme.accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_statusText,
                          style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 12)),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (GithubOAuthService.clientId.startsWith('Ov23liReplaceWith'))
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A2A1A),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFCE9178)),
                      ),
                      child: const Text(
                        'Demo client ID is in use. To enable real sign-in, register a '
                        'GitHub OAuth App with Device Flow enabled and rebuild with '
                        '--dart-define=GITHUB_CLIENT_ID=Ov23li...',
                        style: TextStyle(color: VscodeTheme.fg, fontSize: 11),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
