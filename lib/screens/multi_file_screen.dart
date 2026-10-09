import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/git_file.dart';
import '../providers/repo_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/upload_provider.dart';
import '../services/storage_service.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/file_card.dart';
import '../widgets/path_picker_sheet.dart';
import '../widgets/quick_command_chips.dart';
import '../widgets/send_bottom_bar.dart';
import 'preview_screen.dart';

class MultiFileScreen extends StatefulWidget {
  const MultiFileScreen({super.key});

  @override
  State<MultiFileScreen> createState() => _MultiFileScreenState();
}

class _MultiFileScreenState extends State<MultiFileScreen> {
  final StorageService _storageService = StorageService();
  List<String> _shortcuts = [];

  // Seçim modu: kartlara uzun basınca açılır; kısayol / kaldırma seçililere uygulanır.
  final Set<int> _selectedIds = <int>{};
  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  int _lastTreeRevision = -1;

  @override
  void initState() {
    super.initState();
    _loadShortcuts();
  }

  Future<void> _loadShortcuts() async {
    final list = await _storageService.getShortcuts();
    if (!mounted) return;
    setState(() => _shortcuts = list);
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final List<GitFileItem> items = [];
      for (final f in result.files) {
        final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
        if (bytes != null) {
          items.add(GitFileItem(
            localPath: f.path ?? f.name,
            repoPath: f.name,
            sourceName: f.name,
            size: f.size,
            bytes: bytes,
            status: GitFileStatus.isNew,
          ));
        }
      }

      if (!mounted) return;
      Provider.of<UploadProvider>(context, listen: false).addMultiFiles(items);
    }
  }

  void _showAddShortcutDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni Kısayol Ekle'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Klasör yolu (Örn: lib/core/)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () async {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                final updated = [..._shortcuts, val];
                await _storageService.saveShortcuts(updated);
                if (!mounted) return;
                setState(() => _shortcuts = updated);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _showTextCommandDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Metinle Komut Gir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Formatlar:\n• dosya=hedef/yol\n• klasör/: dosya1.dart dosya2.dart',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 5,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'a.dart=lib/screens/a.dart\nlib/models/: c.dart d.dart',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              Provider.of<UploadProvider>(context, listen: false).parseAndApplyTextCommands(ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
  }

  void _openPathPickerForFile(GitFileItem file) {
    final repoProvider = Provider.of<RepoProvider>(context, listen: false);
    final uploadProvider = Provider.of<UploadProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => PathPickerSheet(
        repoTree: repoProvider.currentTree,
        fileName: file.fileName,
        onPathSelected: (selected) {
          uploadProvider.updateMultiFilePathById(file.id, selected);
        },
      ),
    );
  }

  void _toggleSelection(int id) {
    setState(() {
      if (!_selectedIds.remove(id)) {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _clearAll(UploadProvider upload) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Tümü kaldırılsın mı?',
      content: '${upload.multiFiles.length} dosya listeden kaldırılacak.',
      isDestructive: true,
      confirmLabel: 'Tümünü Kaldır',
    );
    if (!ok || !mounted) return;

    final removed = upload.clearMultiFiles();
    setState(_selectedIds.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${removed.length} dosya kaldırıldı'),
        action: SnackBarAction(
          label: 'Geri Al',
          onPressed: () => upload.restoreMultiFiles(removed),
        ),
      ),
    );
  }

  void _removeSelected(UploadProvider upload) {
    final ids = Set<int>.from(_selectedIds);
    final removed = upload.multiFiles.where((f) => ids.contains(f.id)).toList();
    upload.removeMultiFilesByIds(ids);
    setState(_selectedIds.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${removed.length} dosya kaldırıldı'),
        action: SnackBarAction(
          label: 'Geri Al',
          onPressed: () => upload.restoreMultiFiles(removed),
        ),
      ),
    );
  }

  Future<void> _goToPreview() async {
    final upload = Provider.of<UploadProvider>(context, listen: false);
    if (upload.multiFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir dosya ekleyin.')),
      );
      return;
    }

    await PreviewScreen.open(
      context,
      source: PreviewSource.multi,
      commitMessage: Provider.of<SettingsProvider>(context, listen: false).settings.defaultCommitMessage.isNotEmpty
          ? Provider.of<SettingsProvider>(context, listen: false).settings.defaultCommitMessage
          : 'Gitpush: Çoklu dosya güncellemesi',
    );
  }

  @override
  Widget build(BuildContext context) {
    final upload = Provider.of<UploadProvider>(context);
    final repo = Provider.of<RepoProvider>(context);
    final files = upload.multiFiles;

    // Repo/dal/ağaç değişince (veya ilk açılışta) durumları yeniden hesapla.
    if (_lastTreeRevision != repo.treeRevision) {
      _lastTreeRevision = repo.treeRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        upload.reclassifyAll(repo.treeIndex, truncated: repo.treeTruncated);
      });
    }

    // Kaldırılmış dosyaların seçimlerini temizle
    final liveIds = files.map((f) => f.id).toSet();
    _selectedIds.removeWhere((id) => !liveIds.contains(id));

    final newFolderCount = files.where((f) => f.status == GitFileStatus.newFolder).length;
    final conflictCount = files.where((f) => f.status == GitFileStatus.conflict).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode
            ? '${_selectedIds.length} seçili'
            : 'Çoklu Dosya Güncelle (Mod B)'),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Seçilenleri kaldır',
              onPressed: () => _removeSelected(upload),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Seçimi temizle',
              onPressed: () => setState(_selectedIds.clear),
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.code),
              tooltip: 'Metinle komut gir',
              onPressed: _showTextCommandDialog,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickFiles,
        icon: const Icon(Icons.add),
        label: const Text('Dosya Ekle'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              // Üstte Hazır Komut Çipleri
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: QuickCommandChips(
                  shortcuts: _shortcuts,
                  onSelect: (prefix) {
                    upload.applyShortcutToMultiFiles(prefix, _selectedIds);
                  },
                  onAddShortcut: _showAddShortcutDialog,
                ),
              ),
              if (_isSelectionMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Kısayollar yalnızca seçili ${_selectedIds.length} dosyaya uygulanır.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),

              // Görünür toplu eylem satırı
              if (files.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      Text('${files.length} dosya'),
                      TextButton(
                        onPressed: () => setState(() {
                          _selectedIds
                            ..clear()
                            ..addAll(files.map((f) => f.id));
                        }),
                        child: const Text('Tümünü Seç'),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () => _clearAll(upload),
                        child: const Text('Tümünü Kaldır'),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1),

              // Ağaç alınamadıysa uyarı
              if (repo.treeError != null)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.errorContainer,
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    'Repo dosya listesi alınamadı: ${repo.treeError}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),

              // Dosya Kartları Listesi
              Expanded(
                child: files.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.note_add_outlined, size: 56, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text('Henüz dosya eklenmedi.'),
                            const SizedBox(height: 8),
                            FilledButton.tonal(
                              onPressed: _pickFiles,
                              child: const Text('Telefonunuzdan Dosya Seçin'),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 80),
                        itemCount: files.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final file = files[index];
                          return FileCard(
                            key: ValueKey('card_${file.id}'),
                            file: file,
                            isSelected: _selectedIds.contains(file.id),
                            selectionMode: _isSelectionMode,
                            onToggleSelect: () => _toggleSelection(file.id),
                            onSelectPath: () => _openPathPickerForFile(file),
                            onPathChanged: (newPath) {
                              upload.updateMultiFilePathById(file.id, newPath);
                            },
                            onDelete: () {
                              final removed = file;
                              final removedIndex = files.indexOf(file);
                              upload.removeMultiFile(removedIndex);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${removed.fileName} kaldırıldı'),
                                  action: SnackBarAction(
                                    label: 'Geri Al',
                                    onPressed: () {
                                      upload.restoreMultiFiles([removed], atIndex: removedIndex);
                                    },
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SendBottomBar(
        summaryText:
            '${files.length} dosya${newFolderCount > 0 ? " · $newFolderCount yeni klasör" : ""}${conflictCount > 0 ? " · $conflictCount çakışma" : ""}',
        buttonLabel: 'Önizle',
        onButtonPressed: files.isEmpty ? null : _goToPreview,
      ),
    );
  }
}
