import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PathPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> repoTree;
  final String fileName;
  final ValueChanged<String> onPathSelected;

  const PathPickerSheet({
    super.key,
    required this.repoTree,
    required this.fileName,
    required this.onPathSelected,
  });

  @override
  State<PathPickerSheet> createState() => _PathPickerSheetState();
}

class _PathPickerSheetState extends State<PathPickerSheet> {
  final TextEditingController _newFolderController = TextEditingController();
  String _currentDir = '';

  List<String> get _foldersInCurrentDir {
    final Set<String> dirs = {};
    for (final node in widget.repoTree) {
      if (node['type'] == 'tree') {
        final path = node['path'] as String;
        if (_currentDir.isEmpty) {
          final first = path.split('/')[0];
          dirs.add(first);
        } else if (path.startsWith('$_currentDir/')) {
          final sub = path.substring('$_currentDir/'.length);
          final first = sub.split('/')[0];
          dirs.add(first);
        }
      }
    }
    return dirs.toList()..sort();
  }

  void _navigateTo(String folder) {
    setState(() {
      if (_currentDir.isEmpty) {
        _currentDir = folder;
      } else {
        _currentDir = '$_currentDir/$folder';
      }
    });
  }

  void _navigateUp() {
    setState(() {
      final lastSlash = _currentDir.lastIndexOf('/');
      if (lastSlash == -1) {
        _currentDir = '';
      } else {
        _currentDir = _currentDir.substring(0, lastSlash);
      }
    });
  }

  void _confirmPath(String folder) {
    final full = folder.isEmpty ? widget.fileName : '$folder/${widget.fileName}';
    widget.onPathSelected(full);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Tutamaç
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Başlık ve Breadcrumb
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    if (_currentDir.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: _navigateUp,
                      ),
                    Expanded(
                      child: Text(
                        _currentDir.isEmpty ? '/ (Kök Dizin)' : '/$_currentDir',
                        style: AppTheme.monoBold.copyWith(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _confirmPath(_currentDir),
                      child: const Text('Bu Klasöre Koy'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Yeni Klasör Girişi
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newFolderController,
                        style: AppTheme.monoStyle.copyWith(fontSize: 12),
                        decoration: const InputDecoration(
                          hintText: 'Yeni klasör adı...',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final name = _newFolderController.text.trim();
                        if (name.isNotEmpty) {
                          final target = _currentDir.isEmpty ? name : '$_currentDir/$name';
                          _confirmPath(target);
                        }
                      },
                      child: const Text('Oluştur & Seç'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Klasör Listesi
              Expanded(
                child: _foldersInCurrentDir.isEmpty
                    ? Center(
                        child: Text(
                          'Alt klasör bulunamadı',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _foldersInCurrentDir.length,
                        itemBuilder: (context, index) {
                          final folder = _foldersInCurrentDir[index];
                          return ListTile(
                            leading: Icon(
                              Icons.folder,
                              color: theme.colorScheme.primary,
                            ),
                            title: Text(folder, style: AppTheme.monoStyle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _navigateTo(folder),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
