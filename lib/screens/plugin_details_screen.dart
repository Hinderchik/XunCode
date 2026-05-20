import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app/theme.dart';
import '../models/plugin.dart';
import '../services/plugin_runtime.dart';
import '../services/plugin_service.dart';
import '../services/review_service.dart';

class PluginDetailsScreen extends StatefulWidget {
  final Plugin plugin;
  const PluginDetailsScreen({super.key, required this.plugin});

  @override
  State<PluginDetailsScreen> createState() => _PluginDetailsScreenState();
}

class _PluginDetailsScreenState extends State<PluginDetailsScreen> {
  bool _installing = false;
  bool _installed = false;
  bool _loadingReviews = true;
  List<Review> _reviews = [];
  int _myRating = 5;
  final _reviewCtrl = TextEditingController();
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final results = await Future.wait([
      PluginService.isInstalled(widget.plugin.id),
      ReviewService.fetchReviews(widget.plugin.id),
    ]);
    if (!mounted) return;
    setState(() {
      _installed = results[0] as bool;
      _reviews = results[1] as List<Review>;
      _loadingReviews = false;
    });
  }

  Future<void> _install() async {
    setState(() => _installing = true);
    try {
      final installed = await PluginService.installFromGithub(widget.plugin.githubUrl);
      await PluginRuntime.instance.activate(installed);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${widget.plugin.name} installed'),
        backgroundColor: VscodeTheme.accent,
      ));
      setState(() {
        _installed = true;
        _installing = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Install failed: $e'),
        backgroundColor: VscodeTheme.red,
      ));
      setState(() => _installing = false);
    }
  }

  Future<void> _uninstall() async {
    setState(() => _installing = true);
    await PluginRuntime.instance.deactivate(widget.plugin.id);
    await PluginService.uninstall(widget.plugin.id);
    if (!mounted) return;
    setState(() {
      _installed = false;
      _installing = false;
    });
  }

  Future<void> _postReview() async {
    final text = _reviewCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);
    final ok = await ReviewService.postReview(widget.plugin.id, _myRating, text);
    if (!mounted) return;
    setState(() => _posting = false);
    if (ok) {
      _reviewCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Thanks for the review!'),
        backgroundColor: VscodeTheme.accent,
      ));
      _refresh();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to post review'),
        backgroundColor: VscodeTheme.red,
      ));
    }
  }

  Future<void> _openGithub() async {
    final uri = Uri.parse(widget.plugin.githubUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plugin;
    return Scaffold(
      backgroundColor: VscodeTheme.bg,
      appBar: AppBar(
        title: Text(p.name, style: const TextStyle(fontSize: 15)),
        backgroundColor: VscodeTheme.bgSidebar,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: VscodeTheme.fgMuted),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(p),
          const SizedBox(height: 16),
          _buildActions(),
          const SizedBox(height: 24),
          _buildDescription(p),
          const SizedBox(height: 24),
          _buildReviewsSection(),
        ],
      ),
    );
  }

  Widget _buildHeader(Plugin p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: VscodeTheme.bgSidebar,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: VscodeTheme.border),
          ),
          alignment: Alignment.center,
          child: p.icon != null && p.icon!.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    p.icon!,
                    width: 48, height: 48, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.extension, color: VscodeTheme.accent, size: 28),
                  ),
                )
              : const Icon(Icons.extension, color: VscodeTheme.accent, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name, style: const TextStyle(color: VscodeTheme.fg, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${p.author} · v${p.version}',
                style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 12)),
              const SizedBox(height: 6),
              StarRow(rating: p.rating, reviewsCount: p.reviewsCount, downloads: p.downloads),
              if (p.tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4, runSpacing: 4,
                  children: p.tags.map((t) => _tagChip(t)).toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _tagChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: VscodeTheme.bgInput,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 10)),
      );

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: _installing
              ? const ElevatedButton(
                  onPressed: null,
                  child: SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white)),
                )
              : ElevatedButton.icon(
                  onPressed: _installed ? _uninstall : _install,
                  icon: Icon(_installed ? Icons.delete_outline : Icons.download, size: 16),
                  label: Text(_installed ? 'Uninstall' : 'Install'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _installed ? VscodeTheme.red : VscodeTheme.accent,
                    foregroundColor: Colors.white,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _openGithub,
          icon: const Icon(Icons.open_in_new, size: 14),
          label: const Text('GitHub'),
          style: OutlinedButton.styleFrom(
            foregroundColor: VscodeTheme.accent,
            side: const BorderSide(color: VscodeTheme.border),
          ),
        ),
      ],
    );
  }

  Widget _buildDescription(Plugin p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('DESCRIPTION',
          style: TextStyle(color: VscodeTheme.fgLabel, fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(p.description.isEmpty ? '—' : p.description,
          style: const TextStyle(color: VscodeTheme.fg, fontSize: 13, height: 1.5)),
      ],
    );
  }

  Widget _buildReviewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('REVIEWS',
          style: TextStyle(color: VscodeTheme.fgLabel, fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_installed) _buildReviewForm(),
        const SizedBox(height: 12),
        if (_loadingReviews)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(color: VscodeTheme.accent)),
          )
        else if (_reviews.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No reviews yet', style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 12)),
          )
        else
          ..._reviews.map(_buildReviewItem),
      ],
    );
  }

  Widget _buildReviewForm() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VscodeTheme.bgSidebar,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: VscodeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your review', style: TextStyle(color: VscodeTheme.fg, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            children: List.generate(5, (i) {
              final filled = i < _myRating;
              return GestureDetector(
                onTap: () => setState(() => _myRating = i + 1),
                child: Icon(
                  filled ? Icons.star : Icons.star_border,
                  color: filled ? VscodeTheme.accent : VscodeTheme.fgMuted,
                  size: 22,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reviewCtrl,
            maxLines: 3,
            style: const TextStyle(color: VscodeTheme.fg, fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Share your experience…',
              hintStyle: TextStyle(color: VscodeTheme.fgMuted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _posting ? null : _postReview,
              style: ElevatedButton.styleFrom(
                backgroundColor: VscodeTheme.accent,
                foregroundColor: Colors.white,
              ),
              child: Text(_posting ? 'Sending…' : 'Post review'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewItem(Review r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VscodeTheme.bgSidebar,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: VscodeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(r.author,
                style: const TextStyle(color: VscodeTheme.fg, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              ...List.generate(5, (i) => Icon(
                i < r.rating ? Icons.star : Icons.star_border,
                size: 14,
                color: i < r.rating ? VscodeTheme.accent : VscodeTheme.fgMuted,
              )),
              const Spacer(),
              Text(r.date,
                style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 6),
          Text(r.text, style: const TextStyle(color: VscodeTheme.fg, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}

class StarRow extends StatelessWidget {
  final double rating;
  final int reviewsCount;
  final int downloads;
  const StarRow({super.key, required this.rating, required this.reviewsCount, required this.downloads});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ...List.generate(5, (i) {
          final v = rating - i;
          IconData icon;
          if (v >= 1) {
            icon = Icons.star;
          } else if (v >= 0.5) {
            icon = Icons.star_half;
          } else {
            icon = Icons.star_border;
          }
          return Icon(icon, size: 14, color: VscodeTheme.accent);
        }),
        const SizedBox(width: 4),
        Text(rating.toStringAsFixed(1),
          style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
        const SizedBox(width: 2),
        Text('($reviewsCount)',
          style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
        const SizedBox(width: 12),
        const Icon(Icons.download_outlined, size: 12, color: VscodeTheme.fgMuted),
        const SizedBox(width: 3),
        Text('$downloads',
          style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
      ],
    );
  }
}
