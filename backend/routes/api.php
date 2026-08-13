<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\AssetTypeController;
use App\Http\Controllers\Api\AssetController;
use App\Http\Controllers\Api\AssetSurveyController;
use App\Http\Controllers\Api\ComplaintController;
use App\Http\Controllers\Api\CitizenController;
use App\Http\Controllers\Api\GisController;
use App\Http\Controllers\Api\LocationController;
use App\Http\Controllers\Api\MasterDataController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\RegistrationController;
use App\Http\Controllers\Api\RolePermissionController;
use App\Http\Controllers\Api\UserController;
use App\Http\Controllers\Api\VillageAssetController;
use Illuminate\Support\Facades\Route;

Route::post('/auth/register', [AuthController::class, 'register']);
Route::post('/auth/login', [AuthController::class, 'login'])->middleware('throttle:login');
Route::post('/auth/send-otp', [AuthController::class, 'sendOtp'])->middleware('throttle:otp-send');
Route::post('/auth/resend-otp', [AuthController::class, 'resendOtp'])->middleware('throttle:otp-send');
Route::post('/auth/verify-otp', [AuthController::class, 'verifyOtp'])->middleware('throttle:otp-verify');
Route::post('/auth/forgot-password/request', [AuthController::class, 'forgotPasswordRequest'])->middleware('throttle:forgot-password');
Route::post('/auth/forgot-password/reset', [AuthController::class, 'forgotPasswordReset']);

// Surveyor/Officer registration — basmati-survey-app lifecycle:
// phone OTP → Sign up (pending_email) → email verify link → set password →
// pending_review → admin approve → active.
Route::get('/registrations/districts', [RegistrationController::class, 'districts']);
Route::post('/registrations/phone/send-otp', [RegistrationController::class, 'sendPhoneOtp']);
Route::post('/registrations/phone/verify-otp', [RegistrationController::class, 'verifyPhoneOtp']);
Route::post('/registrations/email/send-link', [RegistrationController::class, 'sendEmailLink']);
Route::get('/registrations/email/verify-link', [RegistrationController::class, 'openEmailVerifyApp']);
Route::post('/registrations/email/verify', [RegistrationController::class, 'verifyEmailLink']);
Route::post('/registrations/set-password', [RegistrationController::class, 'setPassword']);
Route::post('/registrations/surveyor', [RegistrationController::class, 'registerSurveyor']);
Route::post('/registrations/officer', [RegistrationController::class, 'registerOfficer']);
Route::get('/registrations/{id}/status', [RegistrationController::class, 'status']);

// Reverse proxy for HARSAC's Panchayat boundary MapServer - the ArcGIS JS SDK
// calls this directly (no Authorization header), so it can't sit behind
// auth:sanctum. It's not sensitive data (boundary polygons), and the real
// GIS credentials stay server-side either way.
Route::get('/gis/panchayat/{path?}', [GisController::class, 'proxyPanchayat'])->where('path', '.*');
Route::get('/gis/panchayat-vector/{path?}', [GisController::class, 'proxyPanchayatVectorTile'])->where('path', '.*');

Route::middleware('auth:sanctum')->group(function () {
    Route::get('/location/reverse', [LocationController::class, 'reverse']);
    Route::get('/location/resolve', [LocationController::class, 'resolve']);
    Route::get('/auth/me', [AuthController::class, 'me']);
    Route::post('/auth/change-password', [AuthController::class, 'changePassword']);
    Route::get('/users/assignable', [UserController::class, 'assignable']);
    Route::get('/survey-departments', [AssetTypeController::class, 'departments']);
    Route::get('/asset-types', [AssetTypeController::class, 'index']);
    Route::get('/survey-options', [AssetSurveyController::class, 'options']);
    Route::get('/assets', [AssetController::class, 'index']);
    Route::get('/assets/nearby', [AssetController::class, 'nearby']);
    Route::get('/assets/{id}', [AssetController::class, 'show']);
    Route::get('/complaint-categories', [ComplaintController::class, 'categories']);
    Route::get('/surveys', [AssetSurveyController::class, 'index']);
    Route::post('/surveys', [AssetSurveyController::class, 'store']);
    Route::get('/surveys/{id}', [AssetSurveyController::class, 'show']);
    Route::put('/surveys/{id}', [AssetSurveyController::class, 'update']);

    // Master data - read is gated by the master_data.view permission (every
    // role has it by default - dropdowns need it everywhere), write by
    // master_data.manage. Fixed reference-list routes must come before the
    // {entity} wildcard.
    Route::get('/master/roles', [MasterDataController::class, 'roles']);
    Route::get('/master/complaint-statuses', [MasterDataController::class, 'complaintStatuses']);
    Route::get('/master/asset-categories', [MasterDataController::class, 'assetCategories']);
    Route::get('/master/{entity}', [MasterDataController::class, 'index'])
        ->middleware('permission:master_data.view');
    Route::middleware('permission:master_data.manage')->group(function () {
        Route::post('/master/{entity}', [MasterDataController::class, 'store']);
        Route::put('/master/{entity}/{id}', [MasterDataController::class, 'update']);
        Route::delete('/master/{entity}/{id}', [MasterDataController::class, 'destroy']);
        Route::get('/admin/asset-types', [AssetTypeController::class, 'adminIndex']);
        Route::post('/admin/asset-types', [AssetTypeController::class, 'store']);
        Route::put('/admin/asset-types/{id}', [AssetTypeController::class, 'update']);
        Route::delete('/admin/asset-types/{id}', [AssetTypeController::class, 'destroy']);
    });

    // Role/permission management - deliberately gated by role:super_admin
    // (not permission:) so a super_admin can never misconfigure permissions
    // into locking themselves out of the permission editor itself.
    Route::middleware('role:super_admin')->group(function () {
        Route::get('/roles/permissions', [RolePermissionController::class, 'index']);
        Route::put('/roles/{role}/permissions', [RolePermissionController::class, 'update']);
        Route::get('/users', [UserController::class, 'index']);
        Route::get('/citizens', [CitizenController::class, 'index']);
        Route::delete('/citizens/{citizen}', [CitizenController::class, 'destroy']);
        Route::patch('/users/{id}', [UserController::class, 'update']);
        Route::delete('/users/{id}', [UserController::class, 'destroy']);
    });

    // Registration review - district_admin reviews surveyor (engineer)
    // registrations in their own district, state_admin reviews officer
    // registrations, super_admin can review both.
    Route::middleware('role:district_admin,state_admin,super_admin')->group(function () {
        Route::get('/registrations/pending', [RegistrationController::class, 'pending']);
        Route::patch('/registrations/{id}/approve', [RegistrationController::class, 'approve']);
        Route::patch('/registrations/{id}/unapprove', [RegistrationController::class, 'unapprove']);
        Route::patch('/registrations/{id}/reject', [RegistrationController::class, 'reject']);
    });

    // In-app notifications (citizen + staff inbox)
    Route::get('/notifications', [NotificationController::class, 'index']);
    Route::patch('/notifications/{id}/read', [NotificationController::class, 'markRead']);

    // Complaints
    Route::post('/complaints', [ComplaintController::class, 'store'])
        ->middleware('permission:complaints.file');
    Route::get('/complaints/form-options', [ComplaintController::class, 'formOptions'])
        ->middleware('permission:complaints.file');
    Route::get('/complaints/mobile-reports', [ComplaintController::class, 'mobileReports']);
    Route::get('/complaints', [ComplaintController::class, 'index'])
        ->middleware('permission:complaints.view');
    Route::get('/complaints/reports', [ComplaintController::class, 'reports'])
        ->middleware('permission:complaints.view_reports');
    Route::get('/complaints/{id}', [ComplaintController::class, 'show'])
        ->middleware('permission:complaints.view');
    Route::patch('/complaints/{id}/acknowledge', [ComplaintController::class, 'acknowledge'])
        ->middleware('permission:complaints.acknowledge');
    Route::patch('/complaints/{id}/survey', [ComplaintController::class, 'survey'])
        ->middleware('permission:complaints.survey');
    Route::patch('/complaints/{id}/resolve', [ComplaintController::class, 'resolve'])
        ->middleware('permission:complaints.resolve');
    Route::patch('/complaints/{id}/verify', [ComplaintController::class, 'verify'])
        ->middleware('permission:complaints.verify');
    Route::patch('/complaints/{id}/rate', [ComplaintController::class, 'rate'])
        ->middleware('permission:complaints.rate');
    Route::patch('/complaints/{id}/transfer', [ComplaintController::class, 'transfer'])
        ->middleware('permission:complaints.transfer');
    Route::patch('/complaints/{id}/reopen', [ComplaintController::class, 'reopen'])
        ->middleware('permission:complaints.reopen');
    Route::patch('/complaints/{id}/reject', [ComplaintController::class, 'reject'])
        ->middleware('permission:complaints.reject');
    Route::delete('/complaints/{id}', [ComplaintController::class, 'destroy'])
        ->middleware('role:super_admin');

    // Village Assets (GIS infrastructure tracking) - internal to staff roles,
    // not citizen-facing.
    Route::middleware('permission:village_assets.view')->group(function () {
        Route::get('/village-assets', [VillageAssetController::class, 'index']);
        Route::get('/village-assets/{id}', [VillageAssetController::class, 'show']);
    });
    Route::middleware('permission:village_assets.manage')->group(function () {
        Route::post('/village-assets', [VillageAssetController::class, 'store']);
        Route::put('/village-assets/{id}', [VillageAssetController::class, 'update']);
        Route::delete('/village-assets/{id}', [VillageAssetController::class, 'destroy']);
    });
});
