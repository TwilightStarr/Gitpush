import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/repo_provider.dart';
import '../utils/responsive.dart';
import '../widgets/repo_branch_chip.dart';
import 'actions_screen.dart';
import 'history_screen.dart';
import 'repo_browser_screen.dart';
import 'repo_picker_screen.dart';
import 'send_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const List<String> _titles = [
    'Gönder',
    'Repo Tarayıcı',
    'GitHub Actions',
    'Geçmiş',
    'Ayarlar',
  ];

  // Telefon: alt gezinme çubuğu (mevcut davranış).
  static const List<NavigationDestination> _barDestinations = [
    NavigationDestination(
      icon: Icon(Icons.upload_file_outlined),
      selectedIcon: Icon(Icons.upload_file),
      label: 'Gönder',
    ),
    NavigationDestination(
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder),
      label: 'Repo',
    ),
    NavigationDestination(
      icon: Icon(Icons.bolt_outlined),
      selectedIcon: Icon(Icons.bolt),
      label: 'Actions',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history),
      label: 'Geçmiş',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Ayarlar',
    ),
  ];

  // Tablet: yan gezinme çubuğu (NavigationRail), aynı sıra ve etiketlerle.
  static const List<NavigationRailDestination> _railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.upload_file_outlined),
      selectedIcon: Icon(Icons.upload_file),
      label: Text('Gönder'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder),
      label: Text('Repo'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.bolt_outlined),
      selectedIcon: Icon(Icons.bolt),
      label: Text('Actions'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history),
      label: Text('Geçmiş'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: Text('Ayarlar'),
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final repo = Provider.of<RepoProvider>(context, listen: false);
      if (auth.token != null && repo.repositories.isEmpty) {
        repo.loadRepositories(auth.token!);
      }
    });
  }

  void _openRepoPicker() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RepoPickerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repoProvider = Provider.of<RepoProvider>(context);
    final isTablet = Responsive.isTabletSize(MediaQuery.sizeOf(context));

    final content = IndexedStack(
      index: _currentIndex,
      children: [
        const SendScreen(),
        const RepoBrowserScreen(),
        ActionsScreen(isActive: _currentIndex == 2),
        const HistoryScreen(),
        const SettingsScreen(),
      ],
    );

    final appBar = AppBar(
      title: Text(_titles[_currentIndex]),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: RepoBranchChip(
              repoFullName: repoProvider.selectedRepo?.fullName,
              branchName: repoProvider.selectedBranch,
              onTap: _openRepoPicker,
            ),
          ),
        ),
      ],
    );

    if (isTablet) {
      // 11 inç ve benzeri tabletler için: sabit alt bar yerine yan gezinme
      // çubuğu ve içeriğe daha geniş bir maksimum genişlik.
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
              },
              labelType: NavigationRailLabelType.all,
              destinations: _railDestinations,
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: content,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Telefon: mevcut düzen (alt gezinme çubuğu, dar içerik alanı).
    return Scaffold(
      appBar: appBar,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: content,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: _barDestinations,
      ),
    );
  }
}
