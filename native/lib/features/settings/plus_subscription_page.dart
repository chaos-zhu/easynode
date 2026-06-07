import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_result.dart';
import '../../core/ui/palette.dart';
import '../../core/ui/refresh_feedback.dart';
import '../../core/utils/app_store_compliance.dart';
import '../../l10n/app_localizations.dart';
import '../../state/api_providers.dart';
import '../../state/plus_info_notifier.dart';
import 'models/plus_info.dart';

class PlusSubscriptionPage extends ConsumerStatefulWidget {
  const PlusSubscriptionPage({super.key});

  @override
  ConsumerState<PlusSubscriptionPage> createState() =>
      _PlusSubscriptionPageState();
}

class _PlusSubscriptionPageState extends ConsumerState<PlusSubscriptionPage> {
  final _keyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _activating = false;
  bool _prefilled = false;
  PlusDiscount _discount = const PlusDiscount(discount: false, content: '');

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadInitial);
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    if (isIosAppStoreCompliance) return;
    final repo = ref.read(settingsRepositoryProvider);
    try {
      final saved = await repo.getPlusKey();
      if (!mounted) return;
      if (!_prefilled) {
        _keyController.text = saved;
        _prefilled = true;
      }
    } catch (_) {
      // /plus-conf is optional pre-activation — silent fallback.
    }
    if (!isIosAppStoreCompliance) {
      try {
        final discount = await repo.getPlusDiscount();
        if (!mounted) return;
        setState(() => _discount = discount);
      } catch (_) {
        // ignore
      }
    }
  }

  Future<void> _activate() async {
    final l = AppLocalizations.of(context);
    final key = _keyController.text.trim();
    if (key.length < 15) {
      _showSnack(l.tr('plus.keyTooShort'));
      return;
    }
    setState(() => _activating = true);
    try {
      await ref.read(settingsRepositoryProvider).updatePlusKey(key);
      if (!mounted) return;
      _showSnack(l.tr('plus.activateSuccess'));
    } on ApiFailure catch (err) {
      if (!mounted) return;
      // Kicked sessions require a service restart before re-activation.
      _showSnack(err.needRestart ? l.tr('plus.needRestart') : err.message);
    } catch (_) {
      if (!mounted) return;
      _showSnack(l.tr('plus.activateFailed'));
    } finally {
      if (mounted) setState(() => _activating = false);
      await ref.read(plusInfoProvider.notifier).refresh();
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final plusAsync = ref.watch(plusInfoProvider);

    return Scaffold(
      backgroundColor: AppPalette.canvas,
      appBar: AppBar(
        backgroundColor: AppPalette.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(l.tr('settings.plus.title')),
      ),
      body: RefreshIndicator(
        onRefresh: () => runRefreshWithFeedback(context, () async {
          await ref
              .read(plusInfoProvider.notifier)
              .refresh(throwOnError: true);
          await _loadInitial();
        }),
        child: plusAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorBody(
            message: l.trf('plus.loadFailed', [err.toString()]),
            onRetry: () => ref.read(plusInfoProvider.notifier).refresh(),
          ),
          data: (info) => _buildContent(info),
        ),
      ),
    );
  }

  Widget _buildContent(PlusInfo info) {
    final l = AppLocalizations.of(context);
    final iosCompliance = isIosAppStoreCompliance;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _SectionHeader(
          label: l.tr(
            iosCompliance ? 'plus.section.status' : 'plus.section.activate',
          ),
        ),
        if (iosCompliance)
          _AuthorizationStatusCard(info: info)
        else
          _ActivateCard(
            controller: _keyController,
            formKey: _formKey,
            discount: _discount,
            loading: _activating,
            onSubmit: _activate,
          ),
        const SizedBox(height: 18),
        _SectionHeader(label: l.tr('plus.featuresSection')),
        const _FeaturesCard(),
      ],
    );
  }
}

class _AuthorizationStatusCard extends StatelessWidget {
  const _AuthorizationStatusCard({required this.info});

  final PlusInfo info;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final statusText = info.isActive
        ? l.tr('plus.status.active')
        : l.tr('plus.status.inactive');
    final detail = info.error.isNotEmpty
        ? info.error
        : l.tr('plus.status.serverManagedHint');

    return Container(
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                info.isActive
                    ? Icons.verified_outlined
                    : Icons.info_outline_rounded,
                size: 20,
                color: info.isActive ? AppPalette.success : AppPalette.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            detail,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: AppPalette.muted,
            ),
          ),
          const SizedBox(height: 12),
          _StatusLine(label: l.tr('plus.status.label'), value: info.status),
          if (info.instanceId.isNotEmpty) ...[
            const SizedBox(height: 8),
            _StatusLine(
              label: l.tr('plus.status.instance'),
              value: info.instanceId,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppPalette.softMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppPalette.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: AppPalette.muted,
        ),
      ),
    );
  }
}

class _ActivateCard extends StatefulWidget {
  const _ActivateCard({
    required this.controller,
    required this.formKey,
    required this.discount,
    required this.loading,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final GlobalKey<FormState> formKey;
  final PlusDiscount discount;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  State<_ActivateCard> createState() => _ActivateCardState();
}

class _ActivateCardState extends State<_ActivateCard> {
  bool _showKey = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Form(
        key: widget.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.tr('plus.keyLabel').toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: AppPalette.muted,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: widget.controller,
              enabled: !widget.loading,
              obscureText: !_showKey,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => widget.onSubmit(),
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                color: AppPalette.text,
              ),
              decoration: InputDecoration(
                hintText: l.tr('plus.keyHint'),
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: AppPalette.softMuted,
                ),
                isDense: true,
                filled: true,
                fillColor: AppPalette.canvas,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _showKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: AppPalette.muted,
                  ),
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppPalette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppPalette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppPalette.accent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: widget.loading ? null : widget.onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppPalette.primary,
                  foregroundColor: AppPalette.fontOnPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: widget.loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppPalette.fontOnPrimary,
                        ),
                      )
                    : Text(
                        l.tr('plus.activate'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            if (widget.discount.discount && widget.discount.content.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppPalette.dangerSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppPalette.dangerBorder),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 14,
                      color: AppPalette.danger,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.discount.content,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.chip,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: AppPalette.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.tr('plus.activateHint'),
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: AppPalette.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturesCard extends StatelessWidget {
  const _FeaturesCard();

  static const _features = <(IconData, String, String)>[
    (Icons.smart_toy_outlined, 'plus.feature.ai.title', 'plus.feature.ai.desc'),
    (
      Icons.alt_route_outlined,
      'plus.feature.proxy.title',
      'plus.feature.proxy.desc',
    ),
    (
      Icons.desktop_windows_outlined,
      'plus.feature.rdp.title',
      'plus.feature.rdp.desc',
    ),
    (
      Icons.swap_horiz_rounded,
      'plus.feature.transfer.title',
      'plus.feature.transfer.desc',
    ),
    (
      Icons.bolt_outlined,
      'plus.feature.advanced.title',
      'plus.feature.advanced.desc',
    ),
    (
      Icons.web_outlined,
      'plus.feature.web.title',
      'plus.feature.web.desc',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _features.length; i++) ...[
            _FeatureRow(
              icon: _features[i].$1,
              title: l.tr(_features[i].$2),
              description: l.tr(_features[i].$3),
            ),
            if (i < _features.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Divider(height: 1, color: AppPalette.border),
              ),
          ],
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppPalette.chip,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: AppPalette.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: AppPalette.muted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_rounded, size: 16, color: AppPalette.success),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 36,
                  color: AppPalette.danger,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppPalette.text),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => onRetry(),
                  child: Text(l.tr('common.retry')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
