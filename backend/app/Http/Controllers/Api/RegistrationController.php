<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Mail\RegistrationVerificationMail;
use App\Models\District;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;

// Surveyor/Officer registration: verify phone (OTP) and email FIRST, against
// no user record yet - just short-lived cache entries keyed by mobile/email
// - then a single final submit (name, verified phone/email, district,
// password) creates the User directly as pending_review. Admin
// approves/rejects; on approval the account is immediately active.
//
// No real email/SMS provider is wired up, so every "sent" step returns its
// token/OTP directly in the JSON response under a `dev*` key when not in
// production - same convention AuthController::forgotPasswordRequest uses.
class RegistrationController extends Controller
{
    private const OTP_TTL_MINUTES = 10;

    private const EMAIL_TOKEN_TTL_MINUTES = 60 * 24;

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

        $otp = (string) random_int(1000, 9999);
        Cache::put("reg_phone_otp:{$data['mobile']}", $otp, now()->addMinutes(self::OTP_TTL_MINUTES));

        $smsSent = $this->sendOtpSms($data['mobile'], $otp);

        $response = [
            'success' => true,
            'message' => $smsSent ? 'OTP sent to your mobile number' : 'OTP created, but SMS delivery failed',
            'sms_sent' => $smsSent,
        ];
        if (! app()->environment('production')) {
            $response['devOtp'] = $otp;
        }

        return response()->json($response);
    }

    // Pixabits SMS gateway - same account/pattern as the EODB project's
    // otp.controller.js. Delivery failure never blocks the flow: the OTP is
    // already cached, and dev mode still exposes it directly in the response.
    private function sendOtpSms(string $mobile, string $otp): bool
    {
        $apiKey = config('services.pixabits.api_key');
        if (! $apiKey) {
            return false;
        }

        try {
            $senderId = config('services.pixabits.sender_id');
            $http = Http::timeout(10);
            // Local Windows PHP installs commonly lack a CA bundle for cURL
            // ("unable to get local issuer certificate"), which a real Linux
            // deployment won't hit - skip verification only outside production.
            if (! app()->environment('production')) {
                $http = $http->withOptions(['verify' => false]);
            }
            $response = $http->post('https://sms.pixabits.in/smsapi/sms/custom/send', [
                'key' => $apiKey,
                'text' => "Your One Time Password is {$otp} for Mhari Panchayat. Don't share OTP with anyone.{$senderId}",
                'senderId' => $senderId,
                'tempDltId' => config('services.pixabits.dlt_id'),
                'route' => 'Domestic',
                'phoneno' => $mobile,
                'groupIds' => [' '],
                'trans' => 1,
                'unicode' => 0,
                'flash' => false,
                'tiny' => false,
            ]);

            return $response->successful();
        } catch (\Throwable $e) {
            report($e);

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

    public function sendEmailLink(Request $request)
    {
        $data = $request->validate(['email' => ['required', 'email']]);

        $token = Str::random(48);
        Cache::put("reg_email_token:{$data['email']}", $token, now()->addMinutes(self::EMAIL_TOKEN_TTL_MINUTES));

        $emailSent = $this->sendVerificationEmail($data['email'], $token);

        $response = [
            'success' => true,
            'message' => $emailSent ? 'Verification code sent to your email' : 'Verification code created, but email delivery failed',
            'email_sent' => $emailSent,
        ];
        if (! app()->environment('production')) {
            $response['devEmailToken'] = $token;
        }

        return response()->json($response);
    }

    // Mirrors sendOtpSms()'s silent-failure convention: delivery failure never
    // blocks the flow, the token is already cached and dev mode still exposes it.
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

    public function verifyEmailLink(Request $request)
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
            'token' => ['required', 'string'],
        ]);

        $cached = Cache::get("reg_email_token:{$data['email']}");
        if ($cached === null || $cached !== $data['token']) {
            return response()->json(['success' => false, 'message' => 'Invalid or expired verification link'], 400);
        }

        Cache::forget("reg_email_token:{$data['email']}");
        $token = Str::random(40);
        Cache::put("reg_email_verified:{$data['email']}", $token, now()->addMinutes(self::VERIFIED_TOKEN_TTL_MINUTES));

        return response()->json(['success' => true, 'message' => 'Email verified', 'email_token' => $token]);
    }

    /**
     * HTTPS landing page linked from the verification email. Email clients
     * (Gmail/Outlook) block custom-scheme buttons, so the CTA is always https;
     * this page then opens the Flutter app via mharipanchayat:// (and an
     * Android intent:// URL), mirroring basmati-survey-app's openAppBridgeHtml.
     *
     * The token is NOT consumed here — the app still POSTs
     * /registrations/email/verify once it receives the deep link.
     */
    public function openEmailVerifyApp(Request $request)
    {
        $token = trim((string) $request->query('token', ''));
        $email = trim((string) $request->query('email', ''));

        if ($token === '' || $email === '') {
            return response(
                $this->openAppBridgeHtml(
                    heading: 'Invalid link',
                    message: 'This verification link is missing its token or email. Request a new one from the app.',
                    token: '',
                    email: '',
                    autoOpen: false,
                ),
                400,
            )->header('Content-Type', 'text/html; charset=UTF-8');
        }

        // Soft check: warn if token is already gone, but still try to open the
        // app so a previously-verified user can resume the form if needed.
        $cached = Cache::get("reg_email_token:{$email}");
        if ($cached === null || $cached !== $token) {
            return response(
                $this->openAppBridgeHtml(
                    heading: 'Link expired or already used',
                    message: 'Request a new verification email from the app, or paste the code from your email into the Verification Token field.',
                    token: $token,
                    email: $email,
                    autoOpen: false,
                ),
                400,
            )->header('Content-Type', 'text/html; charset=UTF-8');
        }

        return response(
            $this->openAppBridgeHtml(
                heading: 'Open Mhari Panchayat',
                message: 'Opening the app so your email can be verified and you can continue Sign up…',
                token: $token,
                email: $email,
                autoOpen: true,
            )
        )->header('Content-Type', 'text/html; charset=UTF-8');
    }

    private function openAppBridgeHtml(
        string $heading,
        string $message,
        string $token,
        string $email,
        bool $autoOpen,
    ): string {
        $emailQs = $email !== '' ? '&email='.rawurlencode($email) : '';
        $appLink = $token !== ''
            ? 'mharipanchayat://verify-email?token='.rawurlencode($token).$emailQs
            : 'mharipanchayat://verify-email';
        // Matches android/app/build.gradle.kts applicationId for Gram Samadhan.
        $package = 'com.example.my_first_app';
        $intentUrl = 'intent://verify-email?token='.rawurlencode($token).$emailQs
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
      <a class="btn" href="{$safeAppLink}">Open app &amp; verify email</a>
      <p class="footer">If the app does not open, install Mhari Panchayat and tap the button again, or paste the code from your email into Sign up.</p>
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
            'email_token' => ['required', 'string'],
            'district_id' => ['required', 'exists:districts,id'],
            'password' => ['required', 'string', 'min:8'],
        ];
        if ($role === 'department_officer') {
            $rules['employee_id'] = ['required', 'string', 'max:50'];
        }

        $data = $request->validate($rules);

        if (Cache::get("reg_phone_verified:{$data['mobile']}") !== $data['phone_token']) {
            return response()->json(['success' => false, 'message' => 'Phone number is not verified'], 400);
        }
        if (Cache::get("reg_email_verified:{$data['email']}") !== $data['email_token']) {
            return response()->json(['success' => false, 'message' => 'Email is not verified'], 400);
        }

        // Mobile number doubles as the login username - no separate
        // username field in this form.
        $user = User::create([
            'name' => $data['name'],
            'username' => $data['mobile'],
            'email' => $data['email'],
            'mobile' => $data['mobile'],
            'district_id' => $data['district_id'],
            'employee_id' => $data['employee_id'] ?? null,
            'role' => $role,
            'is_active' => false,
            'registration_status' => 'pending_review',
            'password' => $data['password'],
            'email_verified_at' => now(),
            'phone_verified_at' => now(),
        ]);

        Cache::forget("reg_phone_verified:{$data['mobile']}");
        Cache::forget("reg_email_verified:{$data['email']}");

        return response()->json([
            'success' => true,
            'message' => 'Registered. Your account is pending admin review.',
            'user_id' => $user->id,
        ], 201);
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

    // Admin-facing: role-gated (district_admin/state_admin/super_admin) via
    // the route middleware. Scoped here per-role since district_admin and
    // state_admin each only review one registration type.
    public function pending(Request $request)
    {
        $reviewer = $request->user();
        $query = User::with('district')->where('registration_status', 'pending_review');

        if ($reviewer->role === 'district_admin') {
            $query->where('role', 'engineer')->where('district_id', $reviewer->district_id);
        } elseif ($reviewer->role === 'state_admin') {
            $query->where('role', 'department_officer');
        }
        // super_admin sees both types, unscoped.

        return response()->json(['success' => true, 'users' => $query->orderBy('created_at')->get()]);
    }

    private function findReviewable(Request $request, int $id): User|\Illuminate\Http\JsonResponse
    {
        $reviewer = $request->user();
        $user = User::find($id);

        if (! $user || $user->registration_status !== 'pending_review') {
            return response()->json(['success' => false, 'message' => 'No pending registration found'], 404);
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
        $user = $this->findReviewable($request, $id);
        if ($user instanceof \Illuminate\Http\JsonResponse) {
            return $user;
        }

        $user->update([
            'registration_status' => 'active',
            'is_active' => true,
            'reviewed_by_id' => $request->user()->id,
            'reviewed_at' => now(),
        ]);

        return response()->json(['success' => true, 'message' => 'Registration approved. Account is now active.']);
    }

    public function reject(Request $request, int $id)
    {
        $user = $this->findReviewable($request, $id);
        if ($user instanceof \Illuminate\Http\JsonResponse) {
            return $user;
        }

        $data = $request->validate(['reason' => ['required', 'string']]);

        $user->update([
            'registration_status' => 'rejected',
            'rejection_reason' => $data['reason'],
            'reviewed_by_id' => $request->user()->id,
            'reviewed_at' => now(),
        ]);

        return response()->json(['success' => true, 'message' => 'Registration rejected']);
    }
}
