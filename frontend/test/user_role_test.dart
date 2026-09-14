import 'package:flutter_test/flutter_test.dart';
import 'package:mhari_panchayat/models/user_role.dart';

void main() {
  test('fromServerRole sends CPLO to the CPLO shell', () {
    expect(UserRoleStorage.fromServerRole('cplo'), UserRole.cplo);
    expect(UserRoleStorage.fromServerRole('CPLO'), UserRole.cplo);
    expect(UserRoleStorage.fromServerRole('surveyor'), UserRole.survey);
    expect(UserRoleStorage.fromServerRole('engineer'), UserRole.survey);
  });

  test('fromServerRole keeps gram sachiv, citizen and officers distinct', () {
    expect(UserRoleStorage.fromServerRole('gram_sachiv'), UserRole.gramSachiv);
    expect(UserRoleStorage.fromServerRole('citizen'), UserRole.citizen);
    expect(UserRoleStorage.fromServerRole('bdpo'), UserRole.officer);
    expect(UserRoleStorage.fromServerRole('ddpo'), UserRole.officer);
  });

  test('FieldStaffCopy labels CPLO separately from Surveyor', () {
    expect(FieldStaffCopy.isCplo('cplo'), isTrue);
    expect(FieldStaffCopy.roleLabel('cplo'), 'CPLO');
    expect(FieldStaffCopy.profileSubtitle('cplo'), 'CPLO / पंचायत स्तर अधिकारी');
    expect(FieldStaffCopy.surveyTitle('cplo'), 'CPLO Survey');
    expect(FieldStaffCopy.roleLabel('surveyor'), 'Surveyor');
    expect(FieldStaffCopy.surveyTitle('surveyor'), 'Asset Survey');
    expect(FieldStaffCopy.roleLabel(null), '—');
  });
}
