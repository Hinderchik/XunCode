import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/theme.dart';
import '../services/clim_service.dart';
import '../models/settings_model.dart';
import 'package:provider/provider.dart';

class _Message {
  final String role; // 'user' | 'assistant' | 'error'
  final String text;
  _Message(this.role, this.text);
}

class ClimPanel extends StatefulWidget {
  final String selectedCode;
  final String language;
  final VoidCallback onClose;
  final Function(String code)? onInsertCode;
  final bool fillWidth;

  const ClimPanel({
    super.key,
    required this.selectedCode,
    required this.language,
    required this.onClose,
    this.onInsertCode,
    this.fillWidth = false,
  });

  @override
  State<ClimPanel> createState() => _ClimPanelState();
}

class _ClimPanelState extends State<ClimPanel> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_Message> _messages = [];
  final List<Map<String, String>> _history = [];
  bool _loading = false;
  String _explanation = '';
  String _completion = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendChat() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    final settings = context.read<SettingsModel>();
    if (settings.apiKey.isEmpty) { _showApiKeyDialog(); return; }
    _inputCtrl.clear();
    setState(() {
      _messages.add(_Message('user', text));
      _loading = true;
    });
    _scrollToBottom();

    final userContent = widget.selectedCode.isNotEmpty
        ? '```${widget.language}\n${widget.selectedCode}\n```\n\n$text'
        : text;
    _history.add({'role': 'user', 'content': userContent});

    try {
      final reply = await ClimService.sendMessage(
        apiKey: settings.apiKey,
        model: settings.aiModel,
        messages: _history,
      );
      _history.add({'role': 'assistant', 'content': reply});
      setState(() { _messages.add(_Message('assistant', reply)); _loading = false; });
    } catch (e) {
      setState(() { _messages.add(_Message('error', e.toString())); _loading = false; });
    }
    _scrollToBottom();
  }

  Future<void> _explain() async {
    final settings = context.read<SettingsModel>();
    if (settings.apiKey.isEmpty) { _showApiKeyDialog(); return; }
    if (widget.selectedCode.isEmpty) {
      setState(() => _explanation = 'Select code in the editor first.');
      return;
    }
    setState(() { _explanation = ''; _loading = true; });
    try {
      final result = await ClimService.explainCode(
        apiKey: settings.apiKey, model: settings.aiModel,
        code: widget.selectedCode, language: widget.language,
      );
      setState(() { _explanation = result; _loading = false; });
    } catch (e) {
      setState(() { _explanation = 'Error: $e'; _loading = false; });
    }
  }

  Future<void> _complete() async {
    final settings = context.read<SettingsModel>();
    if (settings.apiKey.isEmpty) { _showApiKeyDialog(); return; }
    if (widget.selectedCode.isEmpty) {
      setState(() => _completion = 'Select code prefix in the editor first.');
      return;
    }
    setState(() { _completion = ''; _loading = true; });
    try {
      final result = await ClimService.completeCode(
        apiKey: settings.apiKey, model: settings.aiModel,
        prefix: widget.selectedCode, language: widget.language,
      );
      setState(() { _completion = result; _loading = false; });
    } catch (e) {
      setState(() { _completion = 'Error: $e'; _loading = false; });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _showApiKeyDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VscodeTheme.bgSidebar,
        title: const Text('Anthropic API Key', style: TextStyle(color: VscodeTheme.fg, fontSize: 14)),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          style: const TextStyle(color: VscodeTheme.fg, fontSize: 13),
          decoration: const InputDecoration(hintText: 'sk-ant-...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              context.read<SettingsModel>().set('apiKey', ctrl.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: VscodeTheme.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.fillWidth ? double.infinity : 320,
      decoration: const BoxDecoration(
        color: VscodeTheme.bgSidebar,
        border: Border(left: BorderSide(color: VscodeTheme.border)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_buildChat(), _buildExplain(), _buildComplete()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 35,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: VscodeTheme.bgTab,
        border: Border(bottom: BorderSide(color: VscodeTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 14, color: VscodeTheme.accent),
          const SizedBox(width: 6),
          const Text('CLIM', style: TextStyle(
            fontSize: 11, color: VscodeTheme.fgLabel,
            letterSpacing: 1, fontWeight: FontWeight.w600,
          )),
          const SizedBox(width: 6),
          Consumer<SettingsModel>(
            builder: (_, s, __) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: VscodeTheme.bgInput,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(s.aiModel.split('-').take(2).join('-'),
                style: const TextStyle(fontSize: 10, color: VscodeTheme.fgMuted)),
            ),
          ),
          const Spacer(),
          if (widget.selectedCode.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: VscodeTheme.bgSelection,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('${widget.selectedCode.split('\n').length}L',
                style: const TextStyle(fontSize: 10, color: VscodeTheme.fgVariable)),
            ),
          InkWell(
            onTap: widget.onClose,
            borderRadius: BorderRadius.circular(3),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 14, color: VscodeTheme.fgMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 30,
      color: VscodeTheme.bgTab,
      child: TabBar(
        controller: _tabs,
        labelColor: VscodeTheme.fg,
        unselectedLabelColor: VscodeTheme.fgMuted,
        indicatorColor: VscodeTheme.accent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorWeight: 1,
        labelStyle: const TextStyle(fontSize: 11, letterSpacing: 0.5),
        tabs: const [Tab(text: 'CHAT'), Tab(text: 'EXPLAIN'), Tab(text: 'COMPLETE')],
      ),
    );
  }

  // ── CHAT ──────────────────────────────────────────────────────────────────

  Widget _buildChat() {
    return Column(
      children: [
        if (widget.selectedCode.isNotEmpty) _buildContextBanner(),
        Expanded(
          child: _messages.isEmpty
              ? _buildEmptyChat()
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(0),
                  itemCount: _messages.length + (_loading ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _messages.length) return _buildThinking();
                    return _buildMessage(_messages[i]);
                  },
                ),
        ),
        _buildInput(),
      ],
    );
  }

  Widget _buildContextBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF1A2A3A),
      child: Row(
        children: [
          const Icon(Icons.code, size: 12, color: VscodeTheme.fgVariable),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${widget.selectedCode.split('\n').length} lines of ${widget.language} selected',
              style: const TextStyle(fontSize: 11, color: VscodeTheme.fgVariable),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 32, color: VscodeTheme.fgMuted),
          const SizedBox(height: 12),
          const Text('Ask Clim anything', style: TextStyle(color: VscodeTheme.fg, fontSize: 13)),
          const SizedBox(height: 4),
          const Text('Select code for context', style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
          const SizedBox(height: 16),
          _suggestionChip('Explain this code'),
          _suggestionChip('Find bugs'),
          _suggestionChip('Write unit tests'),
          _suggestionChip('Refactor this'),
        ],
      ),
    );
  }

  Widget _suggestionChip(String label) {
    return GestureDetector(
      onTap: () {
        _inputCtrl.text = label;
        _sendChat();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: VscodeTheme.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, color: VscodeTheme.fgMuted)),
      ),
    );
  }

  Widget _buildThinking() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const SizedBox(width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: VscodeTheme.accent)),
          const SizedBox(width: 8),
          const Text('Clim is thinking…', style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildMessage(_Message msg) {
    final isUser = msg.role == 'user';
    final isError = msg.role == 'error';

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: VscodeTheme.border.withOpacity(0.5))),
        color: isUser ? VscodeTheme.bg : VscodeTheme.bgSidebar,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                  color: isUser ? VscodeTheme.bgSelection
                      : isError ? const Color(0xFF5A1D1D)
                      : const Color(0xFF0E3A1E),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Icon(
                  isUser ? Icons.person : isError ? Icons.error_outline : Icons.auto_awesome,
                  size: 11,
                  color: isUser ? VscodeTheme.fgVariable
                      : isError ? VscodeTheme.red
                      : VscodeTheme.green,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isUser ? 'You' : isError ? 'Error' : 'Clim',
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: isUser ? VscodeTheme.fgVariable
                      : isError ? VscodeTheme.red
                      : VscodeTheme.green,
                ),
              ),
              const Spacer(),
              if (!isUser && !isError)
                InkWell(
                  onTap: () => Clipboard.setData(ClipboardData(text: msg.text)),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.copy, size: 12, color: VscodeTheme.fgMuted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _renderMessageText(msg.text, isError),
        ],
      ),
    );
  }

  Widget _renderMessageText(String text, bool isError) {
    // Split on code blocks and render them differently
    final parts = text.split(RegExp(r'```[\w]*\n?'));
    final widgets = <Widget>[];
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i].trim();
      if (part.isEmpty) continue;
      if (i % 2 == 1) {
        // Code block
        widgets.add(_buildCodeBlock(part));
      } else {
        widgets.add(SelectableText(
          part,
          style: TextStyle(
            fontSize: 12, color: isError ? VscodeTheme.red : VscodeTheme.fg,
            height: 1.5,
          ),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  Widget _buildCodeBlock(String code) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: VscodeTheme.bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: VscodeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: VscodeTheme.border)),
            ),
            child: Row(
              children: [
                const Spacer(),
                InkWell(
                  onTap: () => Clipboard.setData(ClipboardData(text: code)),
                  child: const Row(children: [
                    Icon(Icons.copy, size: 11, color: VscodeTheme.fgMuted),
                    SizedBox(width: 4),
                    Text('Copy', style: TextStyle(fontSize: 10, color: VscodeTheme.fgMuted)),
                  ]),
                ),
                if (widget.onInsertCode != null) ...[
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () => widget.onInsertCode!(code),
                    child: const Row(children: [
                      Icon(Icons.keyboard_tab, size: 11, color: VscodeTheme.accent),
                      SizedBox(width: 4),
                      Text('Insert', style: TextStyle(fontSize: 10, color: VscodeTheme.accent)),
                    ]),
                  ),
                ],
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              code,
              style: const TextStyle(
                fontSize: 12, color: VscodeTheme.fgString,
                fontFamily: 'monospace', height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: VscodeTheme.border)),
        color: VscodeTheme.bg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              style: const TextStyle(color: VscodeTheme.fg, fontSize: 13),
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Message Clim…',
                hintStyle: TextStyle(color: VscodeTheme.fgMuted, fontSize: 12),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                fillColor: Colors.transparent,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
            ),
          ),
          InkWell(
            onTap: _loading ? null : _sendChat,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _loading ? VscodeTheme.bgInput : VscodeTheme.accent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                _loading ? Icons.hourglass_empty : Icons.send,
                size: 14, color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── EXPLAIN ───────────────────────────────────────────────────────────────

  Widget _buildExplain() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.selectedCode.isEmpty
                      ? 'Select code in the editor'
                      : '${widget.selectedCode.split('\n').length} lines selected',
                  style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 12),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _loading ? null : _explain,
                icon: const Icon(Icons.auto_awesome, size: 13),
                label: const Text('Explain', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: VscodeTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: VscodeTheme.border),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: VscodeTheme.accent, strokeWidth: 2))
              : _explanation.isEmpty
                  ? const Center(child: Text('Press Explain to analyze selected code',
                      style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 12)))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: _renderMessageText(_explanation, false),
                    ),
        ),
      ],
    );
  }

  // ── COMPLETE ──────────────────────────────────────────────────────────────

  Widget _buildComplete() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.selectedCode.isEmpty
                      ? 'Select code prefix in editor'
                      : '${widget.selectedCode.split('\n').length} lines as prefix',
                  style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 12),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _loading ? null : _complete,
                icon: const Icon(Icons.auto_fix_high, size: 13),
                label: const Text('Complete', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: VscodeTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: VscodeTheme.border),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: VscodeTheme.accent, strokeWidth: 2))
              : _completion.isEmpty
                  ? const Center(child: Text('Press Complete to generate continuation',
                      style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 12)))
                  : Column(
                      children: [
                        Expanded(child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: _buildCodeBlock(_completion),
                        )),
                        if (widget.onInsertCode != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => widget.onInsertCode!(_completion),
                                icon: const Icon(Icons.keyboard_tab, size: 13),
                                label: const Text('Insert into Editor'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: VscodeTheme.accent,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
        ),
      ],
    );
  }
}
