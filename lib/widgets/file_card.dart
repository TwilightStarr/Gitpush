import 'package:flutter/material.dart';
import '../models/git_file.dart';
import '../theme/app_theme.dart';
import '../utils/path_validation.dart';
import 'status_badge.dart';

class FileCard extends StatefulWidget {
  final GitFileItem file;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback onSelectPath;
  final ValueChanged<String> onPathChanged;
  final VoidCallback onDelete;
  final VoidCallback? onToggleSelect;
  final ValueChanged<String>? onSelectSuggestion;

  const FileCard({
    super.key,
    required this.file,
    this.isSelected = false,
    this.selectionMode = false,
    required this.onSelectPath,
    required this.onPathChanged,
    required this.onDelete,
    this.onToggleSelect,
    this.onSelectSuggestion,
  });

  @override
  State<FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<FileCard> {
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.file.repoPath);
  }

  @override
  void didUpdateWidget(covariant FileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  /// Yol; path picker, öneri çipi, kısayol veya metin komutuyla değiştiğinde
  /// ekrandaki alan da güncellenir (imleç konumu korunur).
  void _syncController() {
    final newText = widget.file.repoPath;
    if (_pathController.text == newText) return;

    final oldSelection = _pathController.selection;
    final offset = oldSelection.isValid && oldSelection.end <= newText.length
        ? oldSelection.end
        : newText.length;
    _pathController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  IconData _getFileIcon(String path) {
    if (path.endsWith('.dart')) return Icons.flutter_dash;
    if (path.endsWith('.yaml') || path.endsWith('.yml')) return Icons.settings_suggest;
    if (path.endsWith('.json')) return Icons.data_object;
    if (path.endsWith('.md')) return Icons.article;
    if (path.endsWith('.png') || path.endsWith('.jpg')) return Icons.image;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = widget.file;

    final hasError = file.status == GitFileStatus.conflict;
    final validation = normalizeAndValidateGitPath(file.targetPath);
    final showResolved = !hasError &&
        validation.isValid &&
        validation.normalizedPath != file.repoPath;

    return Dismissible(
      key: ValueKey('file_${file.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => widget.onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.error),
      ),
      child: Card(
        color: widget.isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: widget.isSelected
              ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Satır 1: İkon + Ad + StatusBadge + Sil butonu
              // (uzun basınca seçim modu, seçim modunda dokununca seç/bırak)
              InkWell(
                onLongPress: widget.onToggleSelect,
                onTap: widget.selectionMode ? widget.onToggleSelect : null,
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    if (widget.selectionMode) ...[
                      Icon(
                        widget.isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Icon(
                      _getFileIcon(file.fileName),
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        file.fileName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (file.statusKnown) StatusBadge(status: file.status),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: widget.onDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Listeden çıkar',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              // Satır 2: Boyut bilgisi
              Text(
                file.formattedSize,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              // Satır 3: Hedef Yol Girişi + Yol Seçici Butonu
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _pathController,
                      style: AppTheme.monoStyle.copyWith(fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Hedef Repo Yolu',
                        hintText: 'lib/screens/a.dart',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        errorText: hasError ? (file.conflictMessage ?? 'Çakışma') : null,
                        errorMaxLines: 3,
                        helperText: showResolved ? '→ ${validation.normalizedPath}' : null,
                      ),
                      onChanged: widget.onPathChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: widget.onSelectPath,
                    icon: const Icon(Icons.folder_open, size: 18),
                    tooltip: 'Repo klasörlerinden seç',
                  ),
                ],
              ),
              // Satır 4: Akıllı Öneri / Uyarı
              if (file.needsChoice) ...[
                const SizedBox(height: 6),
                Text(
                  'Birden fazla eşleşme var, seçin.',
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
                ),
              ],
              if (file.suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Eşleşen:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    ...file.suggestions.take(6).map(
                          (path) => InkWell(
                            onTap: () {
                              widget.onPathChanged(path);
                              widget.onSelectSuggestion?.call(path);
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                path,
                                style: AppTheme.monoStyle.copyWith(
                                  fontSize: 10,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
