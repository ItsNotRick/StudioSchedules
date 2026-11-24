import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/teacher_notes_dao.dart';
import '../domain/teachers.dart';
import '../state/providers.dart';

/// Opens the note editor as a full-screen page on the root navigator, so it
/// works from inside the class detail sheet.
Future<void> openTeacherNoteEditor(
  BuildContext context, {
  required String teacherKey,
  required String listedName,
  required String displayName,
  int? noteId,
  bool combine = false,
}) => Navigator.of(context, rootNavigator: true).push(
  MaterialPageRoute<void>(
    builder: (_) => TeacherNoteEditorPage(
      teacherKey: teacherKey,
      listedName: listedName,
      displayName: displayName,
      noteId: noteId,
      combine: combine,
    ),
  ),
);

/// "Your notes on X": previews of the teacher's notes with add / edit /
/// combine actions. Shows nothing for placeholder teachers such as "Staff".
class TeacherNotesSection extends ConsumerWidget {
  const TeacherNotesSection({
    super.key,
    required this.teacherKey,
    required this.listedName,
    required this.displayName,
    this.showHeading = true,
  });

  final String teacherKey;

  /// The spelling to record on new notes and edits (the class's instructor).
  final String listedName;
  final String displayName;
  final bool showHeading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolver = ref.watch(teacherResolverProvider);
    if (resolver.isPlaceholder(teacherKey)) return const SizedBox.shrink();
    final notes = ref.watch(notesForTeacherProvider(teacherKey));
    final theme = Theme.of(context);

    void open({int? noteId, bool combine = false}) => openTeacherNoteEditor(
      context,
      teacherKey: teacherKey,
      listedName: listedName,
      displayName: displayName,
      noteId: noteId,
      combine: combine,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeading) ...[
            Text(
              'Your notes on $displayName',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
          ],
          if (notes.isEmpty)
            OutlinedButton.icon(
              onPressed: () => open(),
              icon: const Icon(Icons.edit_note),
              label: Text('Add a note about $displayName'),
            ),
          for (final n in notes)
            _NotePreview(
              note: n,
              displayName: displayName,
              spellingLabel: notes.length > 1
                  ? 'Written as ${n.latestName}'
                  : null,
              onTap: () => open(noteId: n.id),
            ),
          if (notes.length > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => open(combine: true),
                icon: const Icon(Icons.merge_type),
                label: Text('Combine ${notes.length} notes'),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotePreview extends StatelessWidget {
  const _NotePreview({
    required this.note,
    required this.displayName,
    required this.onTap,
    this.spellingLabel,
  });

  final TeacherNote note;
  final String displayName;
  final String? spellingLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: 'Edit note on $displayName',
        value: note.body,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (spellingLabel != null)
                        Text(
                          spellingLabel!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                      Text(
                        note.body,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.edit_outlined, size: 18, color: theme.hintColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _Mode { loading, edit, choose, combine }

/// Full-screen note editor.
///
/// - Editing autosaves 600 ms after typing stops, when leaving, and when the
///   app goes to the background. Only one save runs at a time.
/// - Autosave never deletes: leaving with a blank saved note asks whether to
///   delete it or keep the last saved text.
/// - With several notes for the teacher (and no [noteId]), it first asks
///   which to edit, or combines them into text the user reviews and saves.
class TeacherNoteEditorPage extends ConsumerStatefulWidget {
  const TeacherNoteEditorPage({
    super.key,
    required this.teacherKey,
    required this.listedName,
    required this.displayName,
    this.noteId,
    this.combine = false,
  });

  final String teacherKey;
  final String listedName;
  final String displayName;
  final int? noteId;
  final bool combine;

  @override
  ConsumerState<TeacherNoteEditorPage> createState() =>
      _TeacherNoteEditorPageState();
}

class _TeacherNoteEditorPageState extends ConsumerState<TeacherNoteEditorPage> {
  static const _debounce = Duration(milliseconds: 600);

  final _controller = TextEditingController();
  late final TeacherNotesDao _dao;
  late TeacherResolver _resolver;
  late final AppLifecycleListener _lifecycle;
  ScaffoldMessengerState? _messenger;

  _Mode _mode = _Mode.loading;
  List<TeacherNote> _group = const [];
  int? _id;
  int _revision = 0;

  Timer? _timer;
  // Latest text, kept outside the controller so a save that finishes after
  // dispose() can still read it.
  String _text = '';
  bool _dirty = false;
  bool _saving = false;
  bool _closed = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    // Captured here: Riverpod forbids using `ref` in dispose().
    _dao = ref.read(teacherNotesDaoProvider);
    _resolver = ref.read(teacherResolverProvider);
    _lifecycle = AppLifecycleListener(onPause: _flush, onHide: _flush);
    _controller.addListener(_onChanged);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  Future<void> _load() async {
    final all = await _dao.getAll();
    if (!mounted) return;
    final group = notesForTeacher(widget.teacherKey, all, _resolver);
    TeacherNote? target;
    var mode = _Mode.edit;
    if (widget.noteId != null) {
      target = all.where((n) => n.id == widget.noteId).firstOrNull;
    } else if (group.length == 1) {
      target = group.single;
    } else if (group.length > 1) {
      mode = widget.combine ? _Mode.combine : _Mode.choose;
    }
    setState(() {
      _group = group;
      _mode = mode;
      _id = target?.id;
      _revision = target?.revision ?? 0;
      _setText(switch (mode) {
        _Mode.combine => combinedBody(group),
        _ => target?.body ?? '',
      });
    });
  }

  void _setText(String text) {
    _controller.removeListener(_onChanged);
    _controller.text = text;
    _controller.addListener(_onChanged);
    _text = text;
    _dirty = false;
  }

  void _onChanged() {
    if (_controller.text == _text) return;
    final wasBlank = _text.trim().isEmpty;
    // Tracked in every mode so [_text] always matches the field; only edit
    // mode autosaves (combined text is saved explicitly).
    _text = _controller.text;
    if (_mode != _Mode.edit) return;
    // Blankness decides whether leaving needs a confirmation (PopScope).
    if (wasBlank != _text.trim().isEmpty) setState(() {});
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(_debounce, _flush);
  }

  /// Saves the current text if it changed. Never saves a blank note.
  Future<void> _flush() async {
    _timer?.cancel();
    // A save in flight picks up later edits when it finishes.
    if (_mode != _Mode.edit || !_dirty || _saving) return;
    final body = _text;
    if (body.trim().isEmpty) return;
    _dirty = false; // Edits made while saving mark it dirty again.
    _saving = true;
    _setStatus('Saving…');
    try {
      final SaveResult r;
      if (_id == null) {
        r = await _dao.create(listedName: widget.listedName, body: body);
      } else {
        r = await _dao.save(
          id: _id!,
          baseRevision: _revision,
          body: body,
          listedName: widget.listedName,
          forKey: widget.teacherKey,
          resolver: _resolver,
        );
      }
      _id = r.id;
      _revision = r.revision;
      _setStatus('Saved');
      if (r.conflict) {
        _messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'This note changed elsewhere, so your text was saved as a separate note.',
            ),
          ),
        );
      }
    } catch (_) {
      _dirty = true;
      _setStatus('Not saved');
    } finally {
      _saving = false;
    }
    if (!_dirty) return;
    if (_closed) {
      await _flush();
    } else {
      _timer = Timer(_debounce, _flush);
    }
  }

  void _setStatus(String s) {
    if (mounted && !_closed) setState(() => _status = s);
  }

  /// True when leaving would abandon a saved note the user has cleared.
  /// Leaving then asks whether to delete the note; autosave never deletes.
  bool get _clearedSavedNote =>
      _mode == _Mode.edit && _id != null && _text.trim().isEmpty && !_closed;

  /// Leaving the page: save the latest text. (A cleared saved note is
  /// handled by [_confirmLeaveCleared] before the pop happens.)
  Future<void> _onLeave() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    if (_mode != _Mode.edit || _text.trim().isEmpty) return;
    await _flush();
  }

  /// Asks what to do with a cleared note. A dialog rather than an Undo
  /// snackbar: when the editor was opened from the class sheet, a snackbar
  /// would appear behind the sheet's modal barrier.
  Future<void> _confirmLeaveCleared() async {
    final delete = await _askDelete(
      'You cleared your note on ${widget.displayName}.',
      keepLabel: 'Keep note',
    );
    if (delete == null || !mounted) return; // Dismissed: stay and keep editing.
    await _close(delete: delete);
  }

  Future<void> _confirmDelete() async {
    final delete = await _askDelete(
      'Your note on ${widget.displayName} will be deleted.',
      keepLabel: 'Cancel',
    );
    if (delete == true && mounted) await _close(delete: true);
  }

  /// Returns true to delete, false to keep, null if dismissed.
  Future<bool?> _askDelete(String message, {required String keepLabel}) =>
      showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Delete this note?'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(keepLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

  /// Leaves without autosaving. Keeping a cleared note leaves its last saved
  /// text in place (blank text is never saved).
  Future<void> _close({required bool delete}) async {
    _closed = true;
    _timer?.cancel();
    final id = _id;
    if (delete && id != null) await _dao.deleteNote(id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _saveCombined() async {
    final body = _controller.text;
    if (body.trim().isEmpty) {
      _messenger?.showSnackBar(
        const SnackBar(content: Text('The combined note is empty.')),
      );
      return;
    }
    final r = await _dao.combine(
      rows: [for (final n in _group) (n.id, n.revision)],
      body: body,
    );
    if (!mounted) return;
    if (r == null) {
      _messenger?.showSnackBar(
        const SnackBar(
          content: Text('These notes changed. Showing the latest.'),
        ),
      );
      setState(() => _mode = _Mode.loading);
      await _load();
      return;
    }
    setState(() {
      _mode = _Mode.edit;
      _id = r.id;
      _revision = r.revision;
      _group = const [];
      _text = body;
      _dirty = false;
      _status = 'Saved';
    });
  }

  void _editOne(TeacherNote n) => setState(() {
    _mode = _Mode.edit;
    _id = n.id;
    _revision = n.revision;
    _setText(n.body);
  });

  void _startCombine() => setState(() {
    _mode = _Mode.combine;
    _setText(combinedBody(_group));
  });

  @override
  void dispose() {
    _lifecycle.dispose();
    // Covers exits that skip PopScope (e.g. the route being removed).
    if (!_closed) unawaited(_onLeave());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _resolver = ref.watch(teacherResolverProvider);
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_clearedSavedNote,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          unawaited(_onLeave());
        } else {
          unawaited(_confirmLeaveCleared());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.displayName),
              Semantics(
                liveRegion: true,
                child: Text(
                  _mode == _Mode.combine ? 'Combining notes' : _status,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (_mode == _Mode.combine)
              TextButton(onPressed: _saveCombined, child: const Text('Save')),
            if (_mode == _Mode.edit && _id != null)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete note',
                onPressed: _confirmDelete,
              ),
          ],
        ),
        body: switch (_mode) {
          _Mode.loading => const Center(child: CircularProgressIndicator()),
          _Mode.choose => _buildChooser(theme),
          _Mode.edit || _Mode.combine => _buildEditor(theme),
        },
      ),
    );
  }

  Widget _buildChooser(ThemeData theme) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        'You wrote ${_group.length} notes for ${widget.displayName} under different spellings. '
        'Combine them into one, or edit one on its own.',
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _startCombine,
        icon: const Icon(Icons.merge_type),
        label: const Text('Combine'),
      ),
      const SizedBox(height: 16),
      for (final n in _group)
        _NotePreview(
          note: n,
          displayName: widget.displayName,
          spellingLabel: 'Written as ${n.latestName}',
          onTap: () => _editOne(n),
        ),
    ],
  );

  Widget _buildEditor(ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_mode == _Mode.combine)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Review the combined text, then tap Save. Nothing changes until you do.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: TextField(
            controller: _controller,
            autofocus: _id == null && _mode == _Mode.edit,
            expands: true,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText:
                  'What do you want to remember about ${widget.displayName}?\n'
                  'e.g. counts in 7s, lots of floor work, arrive early',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Private to you. Included in your device backup.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
    ),
  );
}
