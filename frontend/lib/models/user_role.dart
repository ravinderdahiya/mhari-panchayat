enum UserRole { citizen, officer, survey, gramSachiv, cplo, verifier }

extension UserRoleStorage on UserRole {
  String get storageValue => name;

  static UserRole? fromStorage(String? value) {
    if (value == null) return null;
    for (final role in UserRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }

  /// Maps the backend `users.role` string onto the field-app shell.
  /// CPLO gets Home / Map / Tasks / Profile; surveyor stays on asset survey.
  /// BDPO/DDPO/XEN-PR/CEO-ZP are the four escalation stages of the asset-
  /// survey verification chain (Gram Sachiv -> BDPO -> DDPO -> XEN-PR (if
  /// technical) -> CEO-ZP) that sit above Gram Sachiv's own stage; they
  /// share one generic "verifier" shell, each seeing only their own stage.
  static UserRole fromServerRole(String? value) {
    final key = (value ?? '').trim().toLowerCase();
    return switch (key) {
      'citizen' => UserRole.citizen,
      'gram_sachiv' => UserRole.gramSachiv,
      'cplo' => UserRole.cplo,
      'surveyor' || 'engineer' => UserRole.survey,
      'bdpo' || 'ddpo' || 'xen_pr' || 'ceo_zp' => UserRole.verifier,
      _ => UserRole.officer,
    };
  }
}

/// Display copy for the field survey shell. CPLO and Surveyor share the
/// same screens; only the identity labels differ.
class FieldStaffCopy {
  static String _key(String? serverRole) =>
      (serverRole ?? '').trim().toLowerCase();

  static bool isCplo(String? serverRole) => _key(serverRole) == 'cplo';

  static String roleLabel(String? serverRole) {
    return switch (_key(serverRole)) {
      'cplo' => 'CPLO',
      'surveyor' || 'engineer' => 'Surveyor',
      '' => '—',
      final key => key.replaceAll('_', ' '),
    };
  }

  static String profileFallbackName(String? serverRole) =>
      isCplo(serverRole) ? 'CPLO' : 'Surveyor';

  static String profileSubtitle(String? serverRole) => switch (_key(serverRole)) {
    'cplo' => 'CPLO / पंचायत स्तर अधिकारी',
    'surveyor' || 'engineer' => 'Field Asset Survey',
    '' => '',
    _ => 'Field Asset Survey',
  };

  static String surveyTitle(String? serverRole) =>
      isCplo(serverRole) ? 'CPLO Survey' : 'Asset Survey';

  static String surveySubtitle(String? serverRole) => isCplo(serverRole)
      ? 'पंचायत स्तर अधिकारी · Live GPS'
      : 'Survey new or existing assets · Live GPS';
}

/// Display copy + queue behaviour for the four verification-escalation
/// roles that share [VerifierShell]: BDPO, DDPO, XEN-PR, CEO-ZP.
class VerifierCopy {
  static String _key(String? serverRole) =>
      (serverRole ?? '').trim().toLowerCase();

  static String roleLabel(String? serverRole) => switch (_key(serverRole)) {
    'bdpo' => 'BDPO',
    'ddpo' => 'DDPO',
    'xen_pr' => 'XEN-PR',
    'ceo_zp' => 'CEO-ZP',
    _ => 'Verifier',
  };

  static String roleSubtitle(String? serverRole) => switch (_key(serverRole)) {
    'bdpo' => 'Block Development & Panchayat Officer',
    'ddpo' => 'District Development & Panchayat Officer',
    'xen_pr' => 'Executive Engineer, Panchayati Raj',
    'ceo_zp' => 'CEO, Zila Parishad',
    _ => 'Survey Verification',
  };

  /// The review_status this role acts on next - the default/primary tab
  /// their verification queue opens to.
  static String inboxStatus(String? serverRole) => switch (_key(serverRole)) {
    'gram_sachiv' => 'pending',
    'bdpo' => 'gram_sachiv_approved',
    'ddpo' => 'bdpo_forwarded',
    'xen_pr' => 'ddpo_approved',
    'ceo_zp' => 'ddpo_approved',
    _ => 'pending',
  };

  /// Status tabs shown in this role's queue: their inbox first, then
  /// what they've already sent on, then terminal states. Covers all five
  /// stages of the escalation chain, Gram Sachiv included, so the queue
  /// screen can look this up the same way regardless of which is signed in.
  static List<(String, String)> statusTabs(String? serverRole) {
    return switch (_key(serverRole)) {
      'gram_sachiv' => const [
        ('pending', 'Pending'),
        ('returned', 'Returned'),
        ('gram_sachiv_approved', 'Verified'),
        ('rejected', 'Rejected'),
      ],
      'bdpo' => const [
        ('gram_sachiv_approved', 'Inbox'),
        ('bdpo_forwarded', 'Forwarded'),
        ('rejected', 'Rejected'),
      ],
      'ddpo' => const [
        ('bdpo_forwarded', 'Inbox'),
        ('ddpo_approved', 'Approved'),
        ('rejected', 'Rejected'),
      ],
      'xen_pr' => const [
        ('ddpo_approved', 'Inbox'),
        ('xen_forwarded', 'Reviewed'),
        ('rejected', 'Rejected'),
      ],
      'ceo_zp' => const [
        ('ddpo_approved', 'Inbox (Direct)'),
        ('xen_forwarded', 'Inbox (Post-XEN)'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
      ],
      _ => const [('pending', 'Pending')],
    };
  }
}

/// One action a verifier can take on a survey at its current stage -
/// resolved per (serverRole, reviewStatus, requiresTechnicalReview) by
/// [SurveyReviewAction.forStage].
enum SurveyReviewActionKind { verify, forward, approve, technicalReview, finalApprove }

class SurveyReviewAction {
  const SurveyReviewAction({required this.kind, required this.label});

  final SurveyReviewActionKind kind;
  final String label;

  /// The single positive action available to [serverRole] on a survey
  /// currently at [reviewStatus], or null if this role has no action to
  /// take right now (wrong stage, or - for XEN-PR/CEO-ZP - the wrong side
  /// of the technical-review branch for this asset type).
  static SurveyReviewAction? forStage({
    required String? serverRole,
    required String reviewStatus,
    required bool requiresTechnicalReview,
  }) {
    final role = (serverRole ?? '').trim().toLowerCase();
    return switch ((role, reviewStatus)) {
      ('gram_sachiv', 'pending') => const SurveyReviewAction(
        kind: SurveyReviewActionKind.verify,
        label: 'Verify',
      ),
      ('bdpo', 'gram_sachiv_approved') => const SurveyReviewAction(
        kind: SurveyReviewActionKind.forward,
        label: 'Forward to DDPO',
      ),
      ('ddpo', 'bdpo_forwarded') => const SurveyReviewAction(
        kind: SurveyReviewActionKind.approve,
        label: 'Approve',
      ),
      ('xen_pr', 'ddpo_approved') when requiresTechnicalReview =>
        const SurveyReviewAction(
          kind: SurveyReviewActionKind.technicalReview,
          label: 'Complete Technical Review',
        ),
      ('ceo_zp', 'ddpo_approved') when !requiresTechnicalReview =>
        const SurveyReviewAction(
          kind: SurveyReviewActionKind.finalApprove,
          label: 'Final Approve',
        ),
      ('ceo_zp', 'xen_forwarded') => const SurveyReviewAction(
        kind: SurveyReviewActionKind.finalApprove,
        label: 'Final Approve',
      ),
      _ => null,
    };
  }

  /// Whether [serverRole] may reject a survey currently at [reviewStatus] -
  /// true exactly when they also own that stage's positive action (or, for
  /// Gram Sachiv, the 'return' action).
  static bool canReject({
    required String? serverRole,
    required String reviewStatus,
    required bool requiresTechnicalReview,
  }) {
    final role = (serverRole ?? '').trim().toLowerCase();
    if (role == 'gram_sachiv' && reviewStatus == 'pending') return true;
    return forStage(
          serverRole: serverRole,
          reviewStatus: reviewStatus,
          requiresTechnicalReview: requiresTechnicalReview,
        ) !=
        null;
  }
}
