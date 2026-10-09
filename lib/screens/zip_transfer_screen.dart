import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/repo_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/upload_provider.dart';
import '../services/zip_service.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/file_tree_view.dart';
import '../widgets/path_picker_sheet.dart';
import '../widgets/section_card.dart';
import '../widgets/send_bottom_bar.dart';
import 'preview_screen.dart';

class ZipTransferScreen extends StatefulWidget {
  const ZipTransferScreen({super.key});

  @override
  State<ZipTransferScreen> createState() => _ZipTransferScreenState();
}

class _ZipTransferScreenState extends State<ZipTransferScreen> {
  late final TextEditingController _targetPathController;
  final TextEditingController _commitMessageController = TextEditingController();

  int _lastTreeRevision = -1;

  @override
  void initState() {
    super.initState();
    final custom = Provider.of<SettingsProvider>(context, listen: false).settings.defaultCommitMessage;
    _commitMessageController.text = custom.isNotEmpty ? custom : 'Gitpush: zip aktarımı';
    final upload = Provider.of<UploadProvider>(context, listen: false);
    _targetPathController = TextEditingController(text: upload.zipPrefix);
  }

  @override
  void dispose() {
    _targetPathController.dispose();
    _commitMessageController.dispose();
    super.dispose();
  }

  Future<void> _pickZipFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);

      if (bytes != null) {
        if (!mounted) return;
        final upload = Provider.of<UploadProvider>(context, listen: false);
        try {
          upload.setZipArchive(fileName: file.name, bytes: bytes);
        } on ZipServiceException catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        }
      }
    }
  }

  void _showPathPicker() {
    final repoProvider = Provider.of<RepoProvider>(context, listen: false);
    final upload = Provider.of<UploadProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => PathPickerSheet(
        repoTree: repoProvider.currentTree,
        fileName: '',
        onPathSelected: (selectedPath) {
          _targetPathController.text = selectedPath;
          upload.setZipPrefix(selectedPath);
        },
      ),
    );
  }

  Future<bool> _onWillPop() async {
    final uploadProvider = Provider.of<UploadProvider>(context, listen: false);
    if (uploadProvider.zipFiles.isNotEmpty) {
      final ok = await ConfirmDialog.show(
        context,
        title: 'Vazgeçilsin mi?',
        content: 'Yüklenen ZIP dosyası ve seçimleriniz sıfırlanacak.',
      );
      if (ok) uploadProvider.resetZip();
      return ok;
    }
    uploadProvider.resetZip();
    return true;
  }

  Future<void> _goToPreview() async {
    final uploadProvider = Provider.of<UploadProvider>(context, listen: false);
    final selectedCount = uploadProvider.zipFiles.where((f) => f.isSelected).length;

    if (selectedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir dosya seçin.')),
      );
      return;
    }

    // Provider'daki nesneler değiştirilmez; önizleme öneklenmiş kopyaları okur.
    await PreviewScreen.open(
      context,
      source: PreviewSource.zip,
      commitMessage: _commitMessageController.text.trim(),
    );
  }

  Future<void> _onDeleteUnlistedChanged(UploadProvider upload, bool value) async {
    if (value) {
      final ok = await ConfirmDialog.show(
        context,
        title: 'Emin misiniz?',
        content: 'Hedef klasör kapsamındaki, ZIP\'te olmayan repo dosyaları silinecek. '
            'Silinecek dosyaları önizlemede tek tek göreceksiniz.',
        isDestructive: true,
      );
      if (ok) upload.setZipDeleteUnlisted(true);
    } else {
      upload.setZipDeleteUnlisted(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uploadProvider = Provider.of<UploadProvider>(context);
    final repo = Provider.of<RepoProvider>(context);
    final files = uploadProvider.zipFiles;
    final selectedCount = files.where((f) => f.isSelected).length;

    // Repo/dal/ağaç değişince (veya ilk açılışta) durumları yeniden hesapla.
    if (_lastTreeRevision != repo.treeRevision) {
      _lastTreeRevision = repo.treeRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        uploadProvider.reclassifyAll(repo.treeIndex, truncated: repo.treeTruncated);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("ZIP'ten Aktar (Mod A)"),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. ZIP Seç Bölümü
                SectionCard(
                  title: '1. ZIP Dosyası',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (uploadProvider.zipFileName == null) ...[
                        OutlinedButton.icon(
                          onPressed: _pickZipFile,
                          icon: const Icon(Icons.file_open_outlined),
                          label: const Text('Telefonunuzdan .ZIP Seçin'),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            const Icon(Icons.archive, color: AppTheme.statusUpdate),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    uploadProvider.zipFileName!,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '${(uploadProvider.zipFileSize / 1024).toStringAsFixed(1)} KB · ${files.length} dosya ayıklandı',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: _pickZipFile,
                              child: const Text('Değiştir'),
                            ),
                          ],
                        ),
                        if (uploadProvider.zipInvalidEntries.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${uploadProvider.zipInvalidEntries.length} girdi geçersiz/güvensiz yol içerdiği için atlandı.',
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Dosyalar Ağacı ve Filtre
                if (files.isNotEmpty) ...[
                  SectionCard(
                    title: '2. Aktarılacak Dosyalar ($selectedCount/${files.length})',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: () => uploadProvider.selectAllZipFiles(true),
                              child: const Text('Tümünü Seç'),
                            ),
                            TextButton(
                              onPressed: () => uploadProvider.selectAllZipFiles(false),
                              child: const Text('Hiçbirini Seçme'),
                            ),
                          ],
                        ),
                        FileTreeView(
                          files: files,
                          onToggle: (index) {
                            uploadProvider.toggleZipFileSelection(
                              index,
                              !files[index].isSelected,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 3. Seçenekler
                SectionCard(
                  title: '3. Aktarım Seçenekleri',
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _targetPathController,
                              style: AppTheme.monoStyle.copyWith(fontSize: 12),
                              onChanged: uploadProvider.setZipPrefix,
                              decoration: const InputDecoration(
                                labelText: 'Hedef Klasör (Boş = Repo Kökü)',
                                hintText: 'örnek: src/ veya packages/app/',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: _showPathPicker,
                            icon: const Icon(Icons.folder_open),
                            tooltip: 'Klasör seç',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("ZIP'in tek üst klasörünü kaldır"),
                        subtitle: const Text('Örn: "proje-master/..." kökünü düzleştirir'),
                        value: uploadProvider.zipStripRootDir,
                        onChanged: uploadProvider.setZipStripRootDir,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Yolları repoya otomatik eşleştir'),
                        subtitle: const Text(
                          'ZIP\'teki fazla/eksik klasörleri repodaki gerçek konuma uydurur '
                          '(Hedef Klasör doluysa devre dışı)',
                        ),
                        value: uploadProvider.zipAutoAlign,
                        onChanged: uploadProvider.setZipAutoAlign,
                      ),
                      if (uploadProvider.zipAlignNotice != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              uploadProvider.zipAlignNotice!,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mevcut dosyaların üzerine yaz'),
                        subtitle: const Text('Kapalıysa repoda zaten var olan yollar atlanır'),
                        value: uploadProvider.zipOverwriteExisting,
                        onChanged: uploadProvider.setZipOverwriteExisting,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Repoda olup ZIP'te olmayanları SİL"),
                        subtitle: const Text(
                          'DİKKAT: Yalnızca hedef klasör (veya ZIP\'in kapsadığı üst klasörler) '
                          'içindeki dosyalar silinir. Önizlemede ayrıca onaylanır.',
                        ),
                        value: uploadProvider.zipDeleteUnlisted,
                        onChanged: (val) => _onDeleteUnlistedChanged(uploadProvider, val),
                      ),
                      if (uploadProvider.zipDeleteNotice != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            uploadProvider.zipDeleteNotice!,
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _commitMessageController,
                        decoration: const InputDecoration(
                          labelText: 'Commit Mesajı',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SendBottomBar(
          summaryText: '$selectedCount dosya seçili',
          buttonLabel: 'Önizle ve Gönder',
          onButtonPressed: files.isEmpty ? null : _goToPreview,
        ),
      ),
    );
  }
}
