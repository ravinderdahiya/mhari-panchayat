<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Mail\RegistrationVerificationMail;
use App\Models\District;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;

// Basmati-survey-app style lifecycle:
//   phone OTP (pre-account) → Sign up creates pending_email user →
//   email verify link → email_verified + password-setup token →
//   set password → pending_review → admin approves → active
class RegistrationController extends Controller
{
    private const OTP_TTL_MINUTES = 10;

    private const EMAIL_TOKEN_TTL_MINUTES = 60 * 24;

    private const PASSWORD_SETUP_TTL_MINUTES = 60 * 24;

    private const VERIFIED_TOKEN_TTL_MINUTES = 120;

    public function districts()
    {
        return response()->json([
            'success' => true,
            'districts' => District::with('state')->orderBy('name')->get(),
        ]);
    }

    public function sendPhoneOtp(Request $request)
    {
        $data = $request->validate([
            'mobile' => ['required', 'string', 'regex:/^[6-9]\d{9}$/'],
        ]);

        if (User::where(function ($q) use ($data) {
            $q->where('username', $data['mobile'])->orWhere('mobile', $data['mobile']);
        })->exists()) {
            return response()->json(['success' => false, 'message' => 'This mobile number is already registered'], 400);
        }

        $otp = (string) random_int(1000, 9999);
        Cache::put("reg_phone_otp:{$data['mobile']}", $otp, now()->addMinutes(self::OTP_TTL_MINUTES));

        $smsSent = $this->sendOtpSms($data['mobile'], $otp);

        $response = [
            'success' => true,
            'message' => $smsSent ? 'OTP sent to your mobile number' : 'OTP created, but SMS delivery failed',
            'smsSent' => $smsSent,
            'sms_sent' => $smsSent,
        ];
        if (! app()->environment('production')) {
            $response['devOtp'] = $otp;
        }

        return response()->json($response);
    }

    private function sendOtpSms(string $mobile, string $otp): bool
    {
        $apiKey = config('services.pixabits.api_key');
        if (! $apiKey) {
            Log::warning('Registration OTP SMS provider is not configured', [
                'api_key' => false,
                'sender_id' => filled(config('services.pixabits.sender_id')),
                'dlt_id' => filled(config('services.pixabits.dlt_id')),
            ]);

            return false;
        }

        try {
            $senderId = config('services.pixabits.sender_id');
            $http = Http::connectTimeout(5)->timeout(12)->retry(3, 600);
            if (! app()->environment('production')) {
                $http = $http->withOptions(['verify' => false]);
            }
            $response = $http->post(config('services.pixabits.url'), [
                'key' => $apiKey,
                'text' => "Your One Time Password is {$otp} for Mhari Panchayat. Don't share OTP with anyone.{$senderId}",
                'senderId' => $senderId,
                'tempDltId' => config('services.pixabits.dlt_id'),
                'route' => config('services.pixabits.route'),
                'phoneno' => $mobile,
                'groupIds' => [' '],
                'trans' => 1,
                'unicode' => 0,
                'flash' => false,
                'tiny' => false,
            ]);

            if (! $response->successful()) {
                Log::warning('Registration OTP SMS provider rejected request', [
                    'provider' => 'pixabits',
                    'status' => $response->status(),
                ]);
            }

            return $response->successful();
        } catch (\Throwable $exception) {
            Log::warning('Registration OTP SMS provider connection failed', [
                'provider' => 'pixabits',
                'exception' => $exception::class,
                'reason' => $exception->getMessage(),
            ]);

            return false;
        }
    }

    public function verifyPhoneOtp(Request $request)
    {
        $data = $request->validate([
            'mobile' => ['required', 'string'],
            'otp' => ['required', 'string'],
        ]);

        $cached = Cache::get("reg_phone_otp:{$data['mobile']}");
        if ($cached === null || $cached !== $data['otp']) {
            return response()->json(['success' => false, 'message' => 'Invalid or expired OTP'], 400);
        }

        Cache::forget("reg_phone_otp:{$data['mobile']}");
        $token = Str::random(40);
        Cache::put("reg_phone_verified:{$data['mobile']}", $token, now()->addMinutes(self::VERIFIED_TOKEN_TTL_MINUTES));

        return response()->json(['success' => true, 'message' => 'Phone verified', 'phone_token' => $token]);
    }

    /** Resend verification email for a pending_email registration (basmati-style). */
    public function sendEmailLink(Request $request)
    {
        $data = $request->validate(['email' => ['required', 'email']]);

        $user = User::where('email', $data['email'])
            ->where('registration_status', 'pending_email')
            ->first();

        if (! $user) {
            return response()->json([
                'success' => false,
                'message' => 'No pending registration found for this email. Complete Sign up first.',
            ], 404);
        }

        $token = Str::random(48);
        $user->update([
            'email_verification_token' => $token,
            'email_verification_expires_at' => now()->addMinutes(self::EMAIL_TOKEN_TTL_MINUTES),
        ]);

        $emailSent = $this->sendVerificationEmail($user->email, $token);

        $response = [
            'success' => true,
            'message' => $emailSent ? 'Verification link sent to your email' : 'Verification link created, but email delivery failed',
            'email_sent' => $emailSent,
        ];
        if (! app()->environment('production')) {
            $response['devEmailToken'] = $token;
        }

        return response()->json($response);
    }

    private function sendVerificationEmail(string $email, string $token): bool
    {
        try {
            Mail::to($email)->send(new RegistrationVerificationMail($token, $email));

            return true;
        } catch (\Throwable $e) {
            report($e);

            return false;
        }
    }

    /**
     * HTTPS email CTA (and in-app deep link with ?format=json).
     * Verifies the email, issues a password-setup token, then opens the app
     * on set-password — same pattern as basmati-survey-app.
     */
    public function openEmailVerifyApp(Request $request)
    {
        $token = trim((string) $request->query('token', ''));
        $wantsJson = $request->query('format') === 'json'
            || $request->header('X-Mhari-App') === '1'
            || $request->expectsJson();

        if ($token === '') {
            if ($wantsJson) {
                return response()->json(['success' => false, 'message' => 'Missing verification token'], 400);
            }

            return response(
                $this->openAppBridgeHtml(
                    heading: 'Invalid link',
                    message: 'This verification link is missing its token. Request a new one from Sign up.',
                    deepLinkPath: 'verify-email',
                    token: '',
                    email: '',
                    autoOpen: false,
                ),
                400,
            )->header('Content-Type', 'text/html; charset=UTF-8');
        }

        $result = $this->completeEmailVerification($token);
        if ($result instanceof \Illuminate\Http\JsonResponse) {
            if ($wantsJson) {
                return $result;
            }
            $payload = $result->getData(true);

            return response(
                $this->openAppBridgeHtml(
                    heading: 'Link expired or already used',
                    message: $payload['message'] ?? 'Request a new verification email from the app.',
                    deepLinkPath: 'set-password',
                    token: '',
                    email: '',
                    autoOpen: false,
                ),
                $result->getStatusCode(),
            )->header('Content-Type', 'text/html; charset=UTF-8');
        }

        ['user' => $user, 'passwordSetupToken' => $setupToken] = $result;

        if ($wantsJson) {
            return response()->json([
                'success' => true,
                'message' => 'Email verified',
                'passwordSetupToken' => $setupToken,
                'email' => $user->email,
                'name' => $user->name,
            ]);
        }

        return response(
            $this->openAppBridgeHtml(
                heading: 'Email verified',
                message: 'Opening Mhari Panchayat so you can set your password…',
                deepLinkPath: 'set-password',
                token: $setupToken,
                email: $user->email,
                autoOpen: true,
            )
        )->header('Content-Type', 'text/html; charset=UTF-8');
    }

    /** Legacy POST kept for older clients — same completion as the GET link. */
    public function verifyEmailLink(Request $request)
    {
        $data = $request->validate([
            'token' => ['required', 'string'],
            'email' => ['nullable', 'email'],
        ]);

        $result = $this->completeEmailVerification($data['token'], $data['email'] ?? null);
        if ($result instanceof \Illuminate\Http\JsonResponse) {
            return $result;
        }

        return response()->json([
            'success' => true,
            'message' => 'Email verified',
            'passwordSetupToken' => $result['passwordSetupToken'],
            'email' => $result['user']->email,
        ]);
    }

    /**
     * @return array{user: User, passwordSetupToken: string}|\Illuminate\Http\JsonResponse
     */
    private function completeEmailVerification(string $token, ?string $email = null): array|\Illuminate\Http\JsonResponse
    {
        $query = User::query()->where('email_verification_token', $token);
        if ($email) {
            $query->where('email', $email);
        }
        $user = $query->first();

        if (! $user) {
            // Already verified: if they still have a fresh set-password token, reuse it.
            $existing = User::query()
                ->when($email, fn ($q) => $q->where('email', $email))
                ->whereNotNull('set_password_token')
                ->where('set_password_token_expires_at', '>', now())
                ->whereIn('registration_status', ['email_verified', 'pending_email'])
                ->first();

            if ($existing && $existing->set_password_token) {
                return [
                    'user' => $existing,
                    'passwordSetupToken' => $existing->set_password_token,
                ];
            }

            return response()->json(['success' => false, 'message' => 'Invalid or expired verification link'], 400);
        }

        if ($user->email_verification_expires_at && $user->email_verification_expires_at->isPast()) {
            return response()->json(['success' => false, 'message' => 'Verification link has expired'], 400);
        }

        $setupToken = Str::random(48);
        $user->update([
            'email_verified_at' => now(),
            'email_verification_token' => null,
            'email_verification_expires_at' => null,
            'registration_status' => 'email_verified',
            'set_password_token' => $setupToken,
            'set_password_token_expires_at' => now()->addMinutes(self::PASSWORD_SETUP_TTL_MINUTES),
        ]);

        return ['user' => $user->fresh(), 'passwordSetupToken' => $setupToken];
    }

    public function setPassword(Request $request)
    {
        $data = $request->validate([
            'token' => ['required', 'string'],
            'password' => ['required', 'string', 'min:8', 'confirmed'],
        ]);

        $user = User::where('set_password_token', $data['token'])->first();
        if (
            ! $user
            || ! $user->set_password_token_expires_at
            || $user->set_password_token_expires_at->isPast()
        ) {
            return response()->json([
                'success' => false,
                'message' => 'This link has expired or was already used.',
            ], 400);
        }

        $user->update([
            'password' => $data['password'],
            'set_password_token' => null,
            'set_password_token_expires_at' => null,
            'registration_status' => 'pending_review',
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Password saved. Wait for admin approval, then Sign in.',
            'email' => $user->email,
        ]);
    }

    private function openAppBridgeHtml(
        string $heading,
        string $message,
        string $deepLinkPath,
        string $token,
        string $email,
        bool $autoOpen,
    ): string {
        $emailQs = $email !== '' ? '&email='.rawurlencode($email) : '';
        $appLink = $token !== ''
            ? 'mharipanchayat://'.$deepLinkPath.'?token='.rawurlencode($token).$emailQs
            : 'mharipanchayat://'.$deepLinkPath;
        $package = 'com.example.my_first_app';
        $intentUrl = 'intent://'.$deepLinkPath.'?token='.rawurlencode($token).$emailQs
            .'#Intent;scheme=mharipanchayat;package='.$package.';end';

        $safeHeading = e($heading);
        $safeMessage = e($message);
        $safeAppLink = e($appLink);
        $jsAppLink = json_encode($appLink, JSON_UNESCAPED_SLASHES);
        $jsIntentUrl = json_encode($intentUrl, JSON_UNESCAPED_SLASHES);
        $autoScript = $autoOpen && $token !== ''
            ? <<<HTML
  <script>
    (function () {
      var appLink = {$jsAppLink};
      var intentUrl = {$jsIntentUrl};
      var isAndroid = /Android/i.test(navigator.userAgent);
      try { window.location.href = isAndroid ? intentUrl : appLink; } catch (e) {}
      setTimeout(function () {
        try { window.location.href = appLink; } catch (e2) {}
      }, 400);
    })();
  </script>
HTML
            : '';

        $btnLabel = $deepLinkPath === 'set-password' ? 'Open app &amp; set password' : 'Open app &amp; verify email';

        return <<<HTML
<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><title>{$safeHeading} · Mhari Panchayat</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { --green:#0D3D2F; --bg:#F7F5EE; --ink:#3A4A43; --muted:#6B7D74; }
  body { margin:0; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif; background:var(--bg); color:var(--ink); }
  .shell { max-width:420px; margin:48px auto; padding:0 20px; }
  .card { background:#fff; border-radius:16px; padding:28px 24px; box-shadow:0 8px 28px rgba(13,61,47,.08); }
  h1 { margin:0 0 10px; font-size:22px; color:var(--green); }
  .lead { margin:0 0 20px; color:var(--muted); line-height:1.45; font-size:15px; }
  .btn { display:block; text-align:center; text-decoration:none; padding:14px 16px; border-radius:12px;
         background:linear-gradient(180deg,#1B5C45,#0D3D2F); color:#fff; font-weight:700; }
  .footer { margin-top:16px; font-size:13px; color:var(--muted); text-align:center; }
</style>
</head>
<body>
  <div class="shell">
    <div class="card">
      <h1>{$safeHeading}</h1>
      <p class="lead">{$safeMessage}</p>
      <a class="btn" href="{$safeAppLink}">{$btnLabel}</a>
      <p class="footer">If the app does not open, install Mhari Panchayat and tap the button again.</p>
    </div>
  </div>
{$autoScript}
</body></html>
HTML;
    }

    private function startRegistration(Request $request, string $role): \Illuminate\Http\JsonResponse
    {
        $rules = [
            'name' => ['required', 'string', 'max:150'],
            'mobile' => ['required', 'string', 'regex:/^[6-9]\d{9}$/', 'unique:users,username'],
            'phone_token' => ['required', 'string'],
            'email' => ['required', 'email', 'unique:users,email'],
            'district_id' => ['required', 'exists:districts,id'],
        ];
        if ($role === 'department_officer') {
            $rules['employee_id'] = ['required', 'string', 'max:50'];
        }

        $data = $request->validate($rules);

        if (Cache::get("reg_phone_verified:{$data['mobile']}") !== $data['phone_token']) {
            return response()->json(['success' => false, 'message' => 'Phone number is not verified'], 400);
        }

        $emailToken = Str::random(48);
        // Placeholder password — replaced after email verify via set-password.
        $user = User::create([
            'name' => $data['name'],
            'username' => $data['mobile'],
            'email' => $data['email'],
            'mobile' => $data['mobile'],
            'district_id' => $data['district_id'],
            'employee_id' => $role === 'engineer' ? null : ($data['employee_id'] ?? null),
            'role' => $role,
            'is_active' => false,
            'registration_status' => 'pending_email',
            'password' => Hash::make(Str::random(64)),
            'phone_verified_at' => now(),
            'email_verification_token' => $emailToken,
            'email_verification_expires_at' => now()->addMinutes(self::EMAIL_TOKEN_TTL_MINUTES),
        ]);

        // Auto emp code for surveyors: SUR-{DISTRICT_CODE}-{USER_ID}
        if ($role === 'engineer') {
            $district = District::find($data['district_id']);
            $distCode = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string) ($district?->code ?: 'GEN')) ?: 'GEN');
            $user->update([
                'employee_id' => sprintf('SUR-%s-%04d', $distCode, $user->id),
            ]);
        }

        Cache::forget("reg_phone_verified:{$data['mobile']}");

        $emailSent = $this->sendVerificationEmail($user->email, $emailToken);

        $response = [
            'success' => true,
            'message' => $emailSent
                ? 'Registration submitted. Check your email to verify, then set your password.'
                : 'Registration submitted, but the verification email could not be sent. Use Resend from the app.',
            'user_id' => $user->id,
            'email_sent' => $emailSent,
        ];
        if (! app()->environment('production')) {
            $response['devEmailToken'] = $emailToken;
        }

        return response()->json($response, 201);
    }

    public function registerSurveyor(Request $request)
    {
        return $this->startRegistration($request, 'engineer');
    }

    public function registerOfficer(Request $request)
    {
        return $this->startRegistration($request, 'department_officer');
    }

    public function status(int $id)
    {
        $user = User::with('district', 'reviewedBy')->find($id);

        if (! $user) {
            return response()->json(['success' => false, 'message' => 'Registration not found'], 404);
        }

        return response()->json([
            'success' => true,
            'registration_status' => $user->registration_status,
            'rejection_reason' => $user->rejection_reason,
            'role' => $user->role,
        ]);
    }

    public function pending(Request $request)
    {
        $reviewer = $request->user();
        $query = User::with('district')->where('registration_status', 'pending_review');

        if ($reviewer->role === 'district_admin') {
            $query->where('role', 'engineer')->where('district_id', $reviewer->district_id);
        } elseif ($reviewer->role === 'state_admin') {
            $query->where('role', 'department_officer');
        }

        return response()->json(['success' => true, 'users' => $query->orderBy('created_at')->get()]);
    }

    private function findReviewable(Request $request, int $id, array $allowedStatuses = ['pending_review']): User|\Illuminate\Http\JsonResponse
    {
        $reviewer = $request->user();
        $user = User::find($id);

        if (! $user || ! in_array($user->registration_status, $allowedStatuses, true)) {
            return response()->json(['success' => false, 'message' => 'No reviewable registration found'], 404);
        }

        $allowed = match ($reviewer->role) {
            'district_admin' => $user->role === 'engineer' && $user->district_id === $reviewer->district_id,
            'state_admin' => $user->role === 'department_officer',
            'super_admin' => true,
            default => false,
        };

        if (! $allowed) {
            return response()->json(['success' => false, 'message' => 'You cannot review this registration'], 403);
        }

        return $user;
    }

    public function approve(Request $request, int $id)
    {
        // pending_review (after set-password) or previously unapproved accounts.
        $user = $this->findReviewable($request, $id, ['pending_review', 'unapproved', 'rejected']);
        if ($user instanceof \Illuminate\Http\JsonResponse) {
            return $user;
        }

        if (in_array($user->registration_status, ['pending_email', 'email_verified'], true)) {
            return response()->json([
                'success' => false,
                'message' => 'Surveyor must verify email and set a password before approval.',
            ], 400);
        }

        $user->update([
            'registration_status' => 'active',
            'is_active' => true,
            'rejection_reason' => null,
            'reviewed_by_id' => $request->user()->id,
            'reviewed_at' => now(),
        ]);

        return response()->json(['success' => true, 'message' => 'Registration approved. Account is now active.']);
    }

    public function unapprove(Request $request, int $id)
    {
        $user = $this->findReviewable($request, $id, ['active']);
        if ($user instanceof \Illuminate\Http\JsonResponse) {
            return $user;
        }

        $data = $request->validate(['reason' => ['nullable', 'string', 'max:500']]);

        $user->update([
            'registration_status' => 'unapproved',
            'is_active' => false,
            'rejection_reason' => $data['reason'] ?? 'Unapproved by admin',
            'reviewed_by_id' => $request->user()->id,
            'reviewed_at' => now(),
        ]);

        return response()->json(['success' => true, 'message' => 'Account unapproved. Surveyor can no longer sign in.']);
    }

    public function reject(Request $request, int $id)
    {
        $user = $this->findReviewable($request, $id, [
            'pending_review',
            'pending_email',
            'email_verified',
            'unapproved',
        ]);
        if ($user instanceof \Illuminate\Http\JsonResponse) {
            return $user;
        }

        $data = $request->validate(['reason' => ['required', 'string']]);

        $user->update([
            'registration_status' => 'rejected',
            'is_active' => false,
            'rejection_reason' => $data['reason'],
            'reviewed_by_id' => $request->user()->id,
            'reviewed_at' => now(),
        ]);

        return response()->json(['success' => true, 'message' => 'Registration rejected']);
    }
}
