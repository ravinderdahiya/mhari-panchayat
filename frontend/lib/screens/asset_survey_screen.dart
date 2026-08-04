import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/asset_type.dart';
import '../models/survey.dart';
import '../models/survey_department.dart';
import '../navigation/app_navigation.dart';
import '../services/survey_api.dart';
import '../theme/app_theme.dart';
import '../utils/asset_icon.dart';
import '../widgets/common_widgets.dart';
import 'asset_survey_form_screen.dart';
import 'surveyor_profile_screen.dart';

class AssetSurveyScreen extends StatefulWidget {
  const AssetSurveyScreen({super.key});

  @override
  State<AssetSurveyScreen> createState() => _AssetSurveyScreenState();
}

class _AssetSurveyScreenState extends State<AssetSurveyScreen> {
  bool _isNewAsset = true;
  bool _loadingDepartments = true;
  bool _loadingTypes = false;
  bool _loadingExisting = false;
  List<SurveyDepartment> _departments = const [];
  int? _selectedDepartmentId;
  List<AssetType> _types = const [];
  List<Survey> _existingAssets = const [];
  String? _selectedId;
  String _existingQuery = '';
  String? _infoMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDepartments());
  }

  Future<void> _loadDepartments() async {
    setState(() {
      _loadingDepartments = true;
      _infoMessage = null;
    });
    try {
      final departments = await SurveyApi.getSurveyDepartments();
      if (!mounted) return;
      setState(() {
        _departments = departments;
        _loadingDepartments = false;
        if (departments.isEmpty) {
          _infoMessage =
              'No departments assigned. Ask admin to assign your department(s).';
        } else if (departments.length == 1) {
          _selectedDepartmentId = departments.first.id;
        }
      });
      if (departments.length == 1) {
        await _loadTypesForDepartment(departments.first.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingDepartments = false;
        _infoMessage = 'Could not load departments. Please try again.';
      });
    }
  }

  Future<void> _loadTypesForDepartment(int departmentId) async {
    setState(() {
      _loadingTypes = true;
      _types = const [];
      _selectedId = null;
      _infoMessage = null;
    });
    try {
      final types = await SurveyApi.getAssetTypes(departmentId: departmentId);
      if (!mounted) return;
      setState(() {
        _types = types;
        _loadingTypes = false;
        if (types.isEmpty) {
          _infoMessage = 'No assets linked to this department yet.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingTypes = false;
        _infoMessage = 'Could not load assets for this department.';
      });
    }
  }

  Future<void> _onDepartmentChanged(int? id) async {
    setState(() {
      _selectedDepartmentId = id;
      _types = const [];
      _selectedId = null;
      _infoMessage = null;
    });
    if (id != null) await _loadTypesForDepartment(id);
  }

  Future<void> _loadExistingAssets() async {
    if (_loadingExisting) return;
    setState(() => _loadingExisting = true);
    try {
      final existing = await SurveyApi.getExistingAssets();
      if (!mounted) return;
      setState(() {
        _existingAssets = existing;
        _loadingExisting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingExisting = false);
    }
  }

  void _switchMode({required bool isNew}) {
    setState(() => _isNewAsset = isNew);
    if (!isNew && _existingAssets.isEmpty) {
      _loadExistingAssets();
    }
  }

  void _onSelect(AssetType type) {
    setState(() => _selectedId = type.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssetSurveyFormScreen(
          departmentId: _selectedDepartmentId!,
          assetTypeId: type.id,
          assetTypeName: type.name,
        ),
      ),
    );
  }

  void _onSelectExisting(Survey survey) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => AssetSurveyFormScreen(
              departmentId: survey.departmentId,
              assetTypeId: survey.assetTypeId,
              assetTypeName: survey.assetTypeName ?? survey.assetTypeId,
              existingSurvey: survey,
            ),
          ),
        )
        .then((_) {
          if (!_isNewAsset) _loadExistingAssets();
        });
  }

  List<Survey> get _filteredExisting {
    final q = _existingQuery.trim().toLowerCase();
    if (q.isEmpty) return _existingAssets;
    return _existingAssets
        .where((s) {
          final typeName = (s.assetTypeName ?? '').toLowerCase();
          final location = '${s.village} ${s.panchayat}'.toLowerCase();
          final description = (s.description ?? '').toLowerCase();
          return typeName.contains(q) ||
              location.contains(q) ||
              description.contains(q) ||
              s.assetName.toLowerCase().contains(q) ||
              s.assetId.toLowerCase().contains(q);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          GradientHeader(
            title: 'Asset Survey',
            subtitle: 'Survey new or existing assets · Live GPS',
            actions: [
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: _LiveBadge(),
              ),
              IconButton(
                icon: const Icon(Icons.account_circle_rounded),
                tooltip: 'Profile',
                onPressed: () => push(context, const SurveyorProfileScreen()),
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded),
                tooltip: 'Logout',
                onPressed: () => handleLogout(context),
              ),
            ],
          ),
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: Material(
                color: AppColors.background,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: _loadingDepartments
                    ? const Center(child: CircularProgressIndicator())
                    : CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _ModeTab(
                                          label: '+ New Asset',
                                          selected: _isNewAsset,
                                          onTap: () => _switchMode(isNew: true),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _ModeTab(
                                          label: '✎ Existing Asset',
                                          selected: !_isNewAsset,
                                          onTap: () =>
                                              _switchMode(isNew: false),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if (_isNewAsset) ...[
                                    Text(
                                      'Select Department *',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF212121),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (_departments.isEmpty)
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: AppColors.orangeTint,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: AppColors.border,
                                          ),
                                        ),
                                        child: Text(
                                          _infoMessage ??
                                              'No departments assigned. Ask admin to assign your department(s).',
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            color: const Color(0xFF5C4A1F),
                                            height: 1.4,
                                          ),
                                        ),
                                      )
                                    else
                                      DropdownButtonFormField<int>(
                                        value: _selectedDepartmentId,
                                        isExpanded: true,
                                        hint: Text(
                                          '-- Choose a department --',
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            color: AppColors.mutedText,
                                          ),
                                        ),
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                        ),
                                        items: [
                                          for (final dept in _departments)
                                            DropdownMenuItem(
                                              value: dept.id,
                                              child: Text(
                                                dept.name,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                        ],
                                        onChanged: _onDepartmentChanged,
                                      ),
                                    if (_selectedDepartmentId != null) ...[
                                      const SizedBox(height: 16),
                                      Text(
                                        'Select Asset Type *',
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF212121),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      if (_loadingTypes)
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 20,
                                          ),
                                          child: Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        )
                                      else if (_types.isEmpty)
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: AppColors.orangeTint,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: AppColors.border,
                                            ),
                                          ),
                                          child: Text(
                                            _infoMessage ??
                                                'No assets linked to this department yet.',
                                            style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              color: const Color(0xFF5C4A1F),
                                              height: 1.4,
                                            ),
                                          ),
                                        )
                                      else ...[
                                        DropdownButtonFormField<String>(
                                          value: _selectedId,
                                          isExpanded: true,
                                          hint: Text(
                                            '-- Choose an asset --',
                                            style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              color: AppColors.mutedText,
                                            ),
                                          ),
                                          decoration: const InputDecoration(
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 14,
                                                  vertical: 12,
                                                ),
                                          ),
                                          items: [
                                            for (final type in _types)
                                              DropdownMenuItem(
                                                value: type.id,
                                                child: Text(
                                                  type.name,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                          ],
                                          onChanged: (id) {
                                            if (id == null) return;
                                            AssetType? match;
                                            for (final t in _types) {
                                              if (t.id == id) {
                                                match = t;
                                                break;
                                              }
                                            }
                                            if (match != null) _onSelect(match);
                                          },
                                        ),
                                        const SizedBox(height: 14),
                                        if (_selectedId == null)
                                          const _PlaceholderCard(),
                                      ],
                                    ],
                                  ] else ...[
                                    TextField(
                                      onChanged: (v) =>
                                          setState(() => _existingQuery = v),
                                      style: GoogleFonts.poppins(fontSize: 14),
                                      decoration: InputDecoration(
                                        hintText: 'Search by asset name',
                                        hintStyle: GoogleFonts.poppins(
                                          color: AppColors.mutedText,
                                          fontSize: 13,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.search_rounded,
                                          color: AppColors.mutedText,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                          borderSide: const BorderSide(
                                            color: AppColors.border,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                          borderSide: const BorderSide(
                                            color: AppColors.border,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (_isNewAsset &&
                              _selectedDepartmentId != null &&
                              !_loadingTypes &&
                              _types.isNotEmpty)
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                14,
                                16,
                                24,
                              ),
                              sliver: SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                      childAspectRatio: 0.82,
                                    ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final type = _types[index];
                                    return _AssetTile(
                                      assetType: type,
                                      selected: type.id == _selectedId,
                                      onTap: () => _onSelect(type),
                                    );
                                  },
                                  childCount: _types.length,
                                  addAutomaticKeepAlives: false,
                                ),
                              ),
                            )
                          else if (_isNewAsset)
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 24),
                            )
                          else if (_loadingExisting)
                            const SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_filteredExisting.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Text(
                                  'No surveyed assets found',
                                  style: GoogleFonts.poppins(
                                    color: AppColors.mutedText,
                                  ),
                                ),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  final survey = _filteredExisting[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _ExistingAssetCard(
                                      survey: survey,
                                      onTap: () => _onSelectExisting(survey),
                                    ),
                                  );
                                }, childCount: _filteredExisting.length),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF66BB6A),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Live',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? AppColors.orangeTint : AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.primary : AppColors.secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.assignment_outlined,
            size: 36,
            color: AppColors.mutedText,
          ),
          const SizedBox(height: 8),
          Text(
            'New Asset Survey',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF212121),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Select an asset type from the dropdown above or tap a tile below to start',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppColors.mutedText,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.assetType,
    required this.selected,
    required this.onTap,
  });

  final AssetType assetType;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tintIndex = assetType.id.hashCode.abs() % 3;
    final Color badgeBg;
    final Color iconColor;
    switch (tintIndex) {
      case 0:
        badgeBg = AppColors.orangeTint;
        iconColor = AppColors.primary;
      case 1:
        badgeBg = AppColors.greenTint;
        iconColor = AppColors.secondary;
      default:
        badgeBg = AppColors.blueTint;
        iconColor = AppColors.inProgressText;
    }

    final borderColor = selected ? AppColors.primary : AppColors.border;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    assetTypeIcon(assetType.iconKey),
                    color: iconColor,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Text(
                    assetType.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF212121),
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExistingAssetCard extends StatelessWidget {
  const _ExistingAssetCard({required this.survey, required this.onTap});

  final Survey survey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typeName = survey.assetTypeName ?? survey.assetTypeId;
    final location = '${survey.village}, ${survey.panchayat}';
    final name = survey.assetName.trim().isNotEmpty
        ? survey.assetName
        : typeName;

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: AppColors.orangeTint,
          foregroundColor: AppColors.primary,
          child: Icon(
            assetTypeIcon(survey.assetTypeIconKey ?? 'apartment'),
            size: 20,
          ),
        ),
        title: Text(
          name,
          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Type: $typeName\nLocation: $location',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AppColors.mutedText,
            height: 1.35,
          ),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
