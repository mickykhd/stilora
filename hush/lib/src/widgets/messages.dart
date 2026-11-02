import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// Hairline day separator with centered uppercase label.
class DayDivider extends StatelessWidget {
  const DayDivider(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final line = Expanded(child: Container(height: 0.5, color: scheme.outlineVariant));
    return Row(children: [
      line,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Aura.spaceMd),
        child: Text(label.toUpperCase(),
            style: Aura.labelSm.copyWith(color: scheme.outline)),
      ),
      line,
    ]);
  }
}

/// Attachment preview card (bento-style inside the stream).
class AttachmentCard extends StatelessWidget {
  const AttachmentCard({super.key, required this.attachment});
  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return AuraCard(
      padding: const EdgeInsets.all(Aura.spaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(Aura.radiusLg),
            ),
            child: Icon(_iconFor(attachment.icon), color: scheme.primary, size: 22),
          ),
          const SizedBox(width: Aura.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(attachment.fileName,
                        overflow: TextOverflow.ellipsis,
                        style: Aura.labelMd.copyWith(color: scheme.onSurface)),
                  ),
                  Text(attachment.sizeLabel,
                      style: Aura.labelSm.copyWith(color: scheme.outline)),
                ]),
                if (attachment.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(attachment.description, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Aura.bodySm
                          .copyWith(color: scheme.onSurfaceVariant)),
                ],
                const SizedBox(height: Aura.spaceSm),
                Wrap(
                  spacing: Aura.spaceMd,
                  runSpacing: Aura.spaceSm,
                  children: [
                    _LinkAction(icon: Icons.visibility, label: 'Inspect Components',
                        color: scheme.primary, onTap: () {}),
                    _LinkAction(icon: Icons.download, label: 'Download',
                        color: scheme.onSurfaceVariant, onTap: () {}),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String name) =>
      name == 'description' ? Icons.description : Icons.grid_view;
}

class _LinkAction extends StatelessWidget {
  const _LinkAction(
      {required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: Aura.bodySm.copyWith(color: color,
              fontWeight: FontWeight.w500)),
        ]),
      );
}

/// Reaction chip: pill with emoji + count; mine = accent border.
class ReactionChip extends StatelessWidget {
  const ReactionChip({super.key, required this.reaction, required this.onTap});
  final Reaction reaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Aura.radiusFull),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Aura.spaceSm, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(Aura.radiusFull),
          border: Border.all(
            color: reaction.mine ? Aura.primaryFixed : scheme.outlineVariant,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(reaction.emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text('${reaction.count}',
              style: Aura.labelSm.copyWith(
                  color: reaction.mine ? Aura.primary : scheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// One row in the message stream (also reused by thread + DM views).
class MessageRow extends StatelessWidget {
  const MessageRow({
    super.key,
    required this.message,
    this.onReact,
    this.onOpenThread,
    this.showAvatar = true,
  });

  final Message message;
  final ValueChanged<Reaction>? onReact;
  final VoidCallback? onOpenThread;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final m = message;
    final failed = m.status == MessageStatus.failed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Aura.spaceSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAvatar) ...[
            AuraAvatar(
              initials: m.author.initials,
              imageUrl: m.author.avatarUrl,
              size: 40,
              ringColor: scheme.surfaceContainerLowest,
            ),
            const SizedBox(width: Aura.spaceMd),
          ] else
            const SizedBox(width: 44),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(Aura.spaceSm),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Aura.radiusXl),
                color: failed
                    ? Aura.errorContainer.withValues(alpha: 0.35)
                    : Colors.transparent,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Meta line
                  Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, children: [
                    Text(m.author.name == 'You' ? 'You' : m.author.name,
                        style: Aura.labelMd
                            .copyWith(fontWeight: FontWeight.w600,
                                color: scheme.onSurface)),
                    Text(m.timeLabel,
                        style: Aura.bodySm.copyWith(color: scheme.outline)),
                    if (m.label != null)
                      AuraChip(m.label!, active: true),
                    if (m.status == MessageStatus.sending)
                      Text('sending…', style: Aura.bodySm
                          .copyWith(color: scheme.outline)),
                  ]),
                  const SizedBox(height: 2),
                  // Body — mentions rendered as accent text
                  RichText(
                    text: _body(context, m.text),
                    maxLines: 20,
                  ),
                  if (m.attachment != null) ...[
                    const SizedBox(height: Aura.spaceSm + 4),
                    AttachmentCard(attachment: m.attachment!),
                  ],
                  // Reactions + thread entry
                  if (m.reactions.isNotEmpty || m.replyCount > 0) ...[
                    const SizedBox(height: Aura.spaceSm),
                    Wrap(spacing: Aura.spaceSm, runSpacing: 4, children: [
                      for (final r in m.reactions)
                        ReactionChip(
                          reaction: r,
                          onTap: () => onReact?.call(r),
                        ),
                      if (m.replyCount > 0)
                        InkWell(
                          onTap: onOpenThread,
                          borderRadius: BorderRadius.circular(Aura.radiusFull),
                          child: AuraChip('${m.replyCount} replies',
                              icon: Icons.chat_bubble_outline),
                        ),
                    ]),
                  ],
                  if (failed)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        Icon(Icons.error_outline, size: 14, color: Aura.error),
                        const SizedBox(width: 4),
                        Text('Not sent',
                            style: Aura.labelSm.copyWith(color: Aura.error)),
                        const SizedBox(width: Aura.spaceSm),
                        InkWell(onTap: () {},
                            child: Text('Retry',
                                style: Aura.labelSm.copyWith(
                                    color: scheme.primary))),
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Renders `#mentions` and `**bold**`-free plain text with accent mentions.
  InlineSpan _body(BuildContext context, String text) {
    final scheme = ColorScheme.of(context);
    final base = Aura.bodyLg.copyWith(color: scheme.onSurface, height: 1.5);
    final mentionStyle =
        Aura.bodyLg.copyWith(color: scheme.primary, fontWeight: FontWeight.w600);
    final spans = <InlineSpan>[];
    final re = RegExp(r'(#[\w:]+)');
    var index = 0;
    for (final match in re.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      spans.add(TextSpan(text: match.group(0), style: mentionStyle));
      index = match.end;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));
    return TextSpan(style: base, children: spans);
  }
}

/// Message composer (bottom of chat / DM / thread).
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.hint,
    this.onSend,
  });

  final String hint;
  final ValueChanged<String>? onSend;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend?.call(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.all(Aura.spaceSm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Aura.radiusXl),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(children: [
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 6,
          onSubmitted: (_) => _send(),
          style: Aura.bodyMd.copyWith(color: scheme.onSurface),
          decoration: InputDecoration(
            filled: false,
            hintText: widget.hint,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.all(Aura.spaceSm),
          ),
        ),
        Divider(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            _tool(Icons.attach_file, 'Attach file', () {}),
            _tool(Icons.format_italic, 'Format markdown', () {}),
            _tool(Icons.code, 'Insert snippet', () {}),
            _tool(Icons.mood, 'Emoji', () {}),
            const Spacer(),
            Text('Return to send',
                style: Aura.labelSm.copyWith(color: scheme.outline)),
            const SizedBox(width: Aura.spaceSm),
            FilledButton.icon(
              onPressed: _send,
              style: FilledButton.styleFrom(
                backgroundColor: Aura.primary,
                foregroundColor: Aura.onPrimary,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(
                    horizontal: Aura.spaceMd, vertical: 8),
              ),
              icon: const Icon(Icons.arrow_upward, size: 14),
              label: const Text('Send'),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _tool(IconData icon, String tooltip, VoidCallback onTap) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        visualDensity: VisualDensity.compact,
      );
}
