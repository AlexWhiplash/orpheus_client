import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:orpheus_project/l10n/app_localizations.dart';
import 'package:orpheus_project/models/note_model.dart';
import 'package:orpheus_project/services/database_service.dart';
import 'package:orpheus_project/theme/app_tokens.dart';
import 'package:orpheus_project/widgets/app_dialog.dart';
import 'package:orpheus_project/widgets/app_scaffold.dart';

class NotesVaultScreen extends StatefulWidget {
  const NotesVaultScreen({super.key});

  @override
  State<NotesVaultScreen> createState() => _NotesVaultScreenState();
}

class _NotesVaultScreenState extends State<NotesVaultScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Future<List<NoteEntry>> _loadNotes() async {
    final rows = await DatabaseService.instance.getNotes();
    return rows.map(NoteEntry.fromMap).toList(growable: false);
  }

  Future<void> _addNote() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.selectionClick();
    _controller.clear();
    await DatabaseService.instance.addNote(
      text: text,
      sourceType: NoteSourceType.manual.name,
    );
    if (!mounted) return;
    setState(() {});
    _scrollToTop();
  }

  Future<void> _showNoteActions(NoteEntry note) async {
    final l10n = L10n.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Редактировать — только свои (manual) заметки: пересланные/из Oracle
              // оставляем как есть (иначе метка источника разойдётся с текстом).
              if (note.sourceType == NoteSourceType.manual)
                ListTile(
                  leading:
                      const Icon(Icons.edit_outlined, color: AppColors.action),
                  title: Text(l10n.editNote),
                  onTap: () => Navigator.pop(context, 'edit'),
                ),
              ListTile(
                leading: const Icon(Icons.copy, color: AppColors.action),
                title: Text(l10n.copy),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppColors.danger),
                title: Text(l10n.delete, style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: note.text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.copied)),
      );
    } else if (action == 'edit' && note.id != null) {
      await _editNote(note);
    } else if (action == 'delete' && note.id != null) {
      final ok = await AppDialog.show(
        context: context,
        icon: Icons.delete_outline,
        title: l10n.notesDeleteTitle,
        content: l10n.notesDeleteDesc,
        primaryLabel: l10n.delete,
        secondaryLabel: l10n.cancel,
        isDanger: true,
      );
      if (!ok) return;
      await DatabaseService.instance.deleteNote(note.id!);
      if (!mounted) return;
      setState(() {});
    }
  }

  /// Редактирование текста своей (manual) заметки.
  Future<void> _editNote(NoteEntry note) async {
    final l10n = L10n.of(context);
    final controller = TextEditingController(text: note.text);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(l10n.editNote),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          minLines: 3,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: l10n.notesPlaceholder,
            hintStyle: const TextStyle(color: AppColors.textTertiary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    final newText = controller.text;
    controller.dispose();
    if (saved == true && note.id != null && newText.trim().isNotEmpty) {
      await DatabaseService.instance.updateNote(id: note.id!, text: newText);
      if (!mounted) return;
      setState(() {});
    }
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppScaffold(
      safeArea: false,
      appBar: AppBar(
        title: Text(l10n.notesVaultTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<NoteEntry>>(
              future: _loadNotes(),
              builder: (context, snapshot) {
                final notes = snapshot.data ?? const <NoteEntry>[];
                if (notes.isEmpty) {
                  return _EmptyVault(l10n: l10n);
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.xl,
                  ),
                  itemCount: notes.length,
                  itemBuilder: (context, index) {
                    final note = notes[index];
                    return _NoteCard(
                      note: note,
                      onLongPress: () => _showNoteActions(note),
                    );
                  },
                );
              },
            ),
          ),
          _InputBar(
            controller: _controller,
            onSend: _addNote,
          ),
        ],
      ),
    );
  }
}

class _EmptyVault extends StatelessWidget {
  const _EmptyVault({required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: 42, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(l10n.notesEmptyTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              l10n.notesEmptyDesc,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, this.onLongPress});

  final NoteEntry note;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final sourceLabel = _buildSourceLabel(l10n);
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.md,
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sourceLabel != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.action.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.action.withOpacity(0.25)),
                ),
                child: Text(
                  sourceLabel,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppColors.action),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              note.text,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat('dd.MM.yyyy, HH:mm').format(note.createdAt),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  String? _buildSourceLabel(L10n l10n) {
    switch (note.sourceType) {
      case NoteSourceType.contact:
        return l10n.notesFromContact(note.sourceLabel ?? '');
      case NoteSourceType.room:
        return l10n.notesFromRoom(note.sourceLabel ?? '');
      case NoteSourceType.oracle:
        return l10n.notesFromOracle;
      case NoteSourceType.manual:
        return null;
    }
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: l10n.notesPlaceholder,
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.newline,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send_rounded, color: AppColors.primary),
              onPressed: onSend,
              tooltip: l10n.notesAdd,
            ),
          ],
        ),
      ),
    );
  }
}
