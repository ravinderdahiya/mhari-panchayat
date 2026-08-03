<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PasswordResetToken;
use App\Models\CitizenProfile;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class AuthController extends Controller
{
    private const CITIZEN_OTP_TTL_MINUTES = 10;

    private const CITIZEN_OTP_RESEND_COOLDOWN_SECONDS = 30;

    private const CITIZEN_OTP_MAX_ATTEMPTS = 5;

    public function register(Request $request)
    {
        $data = $request->validate([
            'username' => ['required', 'string', 'min:3', 'unique:users,username'],
            'password' => ['required', 'string', 'min:8'],
            'name' => ['nullable', 'string'],
            'email' => ['nullable', 'email'],
        ]);

        $user = User::create($data);
        $token = $user->createToken('auth')->plainTextToken;

        return response()->json([
            'success' => true,
            'message' => 'Registered successfully',
            'token' => $token,
            'user' => $user,
        ], 201);
    }

    private function citizenOtpKey(string $mobile): string
    {
        return "citizen_login_otp:{$mobile}";
    }

    private function citizenOtpAttemptsKey(string $mobile): string
    {
        return "citizen_login_otp_attempts:{$mobile}";
    }

    private function citizenOtpResendKey(string $mobile): string
    {
        return "citizen_login_otp_resend_at:{$mobile}";
    }

    private function sendOtpSms(string $mobile, string $otp): bool
    {
        $apiKey = config('services.pixabits.api_key');
        if (! $apiKey) {
            Log::warning('Citizen OTP SMS provider is not configured', [
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
                Log::warning('Citizen OTP SMS provider rejected request', [
                    'provider' => 'pixabits',
                    'status' => $response->status(),
                ]);
            }

            return $response->successful();
        } catch (\Throwable $exception) {
            Log::warning('Citizen OTP SMS provider connection failed', [
                'provider' => 'pixabits',
                'exception' => $exception::class,
                'reason' => $exception->getMessage(),
            ]);

            return false;
        }
    }

    private function issueCitizenOtp(Request $request, bool $resend = false)
    {
        $data = $request->validate([
            'mobile' => ['required', 'string', 'regex:/^[6-9]\d{9}$/'],
        ]);
        $mobile = $data['mobile'];

        $existingUser = User::query()
            ->where('mobile', $mobile)
            ->orWhere('username', $mobile)
            ->first();
        if ($existingUser && $existingUser->role !== 'citizen') {
            return response()->json([
                'success' => false,
                'message' => 'This mobile number belongs to a staff account. Use Staff Login.',
            ], 422);
        }

        $resendAvailableAt = (int) Cache::get($this->citizenOtpResendKey($mobile), 0);
        $retryAfter = max(0, $resendAvailableAt - now()->timestamp);
        if ($resend && $retryAfter > 0) {
            return response()->json([
                'success' => false,
                'message' => "Please wait {$retryAfter} seconds before requesting another OTP.",
                'retryAfter' => $retryAfter,
            ], 429);
        }

        $otp = (string) random_int(1000, 9999);
        Cache::put($this->citizenOtpKey($mobile), $otp, now()->addMinutes(self::CITIZEN_OTP_TTL_MINUTES));
        Cache::put($this->citizenOtpAttemptsKey($mobile), 0, now()->addMinutes(self::CITIZEN_OTP_TTL_MINUTES));
        $nextResendAt = now()->addSeconds(self::CITIZEN_OTP_RESEND_COOLDOWN_SECONDS);
        Cache::put(
            $this->citizenOtpResendKey($mobile),
            $nextResendAt->timestamp,
            $nextResendAt,
        );
        $smsSent = $this->sendOtpSms($mobile, $otp);

        $message = $smsSent
            ? ($resend ? 'OTP resent to your mobile number' : 'OTP sent to your mobile number')
            : 'OTP created, but SMS delivery failed';
        if (! $smsSent && ! app()->environment('production')) {
            $message .= ". Development OTP: {$otp}";
        }

        $response = [
            'success' => true,
            'message' => $message,
            'smsSent' => $smsSent,
            'sms_sent' => $smsSent,
            'expiresIn' => self::CITIZEN_OTP_TTL_MINUTES * 60,
            'expires_in' => self::CITIZEN_OTP_TTL_MINUTES * 60,
            'resendAfter' => self::CITIZEN_OTP_RESEND_COOLDOWN_SECONDS,
            'resend_after' => self::CITIZEN_OTP_RESEND_COOLDOWN_SECONDS,
        ];
        if (! app()->environment('production')) {
            $response['devOtp'] = $otp;
        }

        return response()->json($response);
    }

    public function sendOtp(Request $request)
    {
        return $this->issueCitizenOtp($request);
    }

    public function resendOtp(Request $request)
    {
        return $this->issueCitizenOtp($request, true);
    }

    public function verifyOtp(Request $request)
    {
        $data = $request->validate([
            'mobile' => ['required', 'string', 'regex:/^[6-9]\d{9}$/'],
            'otp' => ['required', 'string', 'regex:/^\d{4}$/'],
        ]);
        $mobile = $data['mobile'];
        $isLocalTestLogin = ! app()->environment('production')
            && $mobile === '9999999999'
            && $data['otp'] === '0000';

        if (! $isLocalTestLogin) {
            $cachedOtp = Cache::get($this->citizenOtpKey($mobile));
            $attempts = Cache::increment($this->citizenOtpAttemptsKey($mobile));
            if ($attempts > self::CITIZEN_OTP_MAX_ATTEMPTS) {
                Cache::forget($this->citizenOtpKey($mobile));
                Cache::forget($this->citizenOtpAttemptsKey($mobile));

                return response()->json([
                    'success' => false,
                    'message' => 'Too many incorrect attempts. Request a new OTP.',
                ], 429);
            }

            if (! is_string($cachedOtp) || ! hash_equals($cachedOtp, $data['otp'])) {
                return response()->json(['success' => false, 'message' => 'Invalid or expired OTP'], 400);
            }
        }

        Cache::forget($this->citizenOtpKey($mobile));
        Cache::forget($this->citizenOtpAttemptsKey($mobile));
        Cache::forget($this->citizenOtpResendKey($mobile));

        $user = User::query()
            ->where('mobile', $mobile)
            ->orWhere('username', $mobile)
            ->first();
        if ($user && $user->role !== 'citizen') {
            return response()->json([
                'success' => false,
                'message' => 'This mobile number belongs to a staff account. Use Staff Login.',
            ], 422);
        }

        if (! $user) {
            $user = User::create([
                'username' => $mobile,
                'mobile' => $mobile,
                'name' => 'Citizen '.substr($mobile, -4),
                'password' => Str::random(40),
                'role' => 'citizen',
                'is_active' => true,
                'registration_status' => 'active',
                'phone_verified_at' => now(),
            ]);
        } else {
            if ($user->registration_status === 'rejected') {
                return response()->json(['success' => false, 'message' => 'Citizen account is rejected'], 403);
            }
            if ($user->registration_status !== 'active' || ! $user->is_active) {
                return response()->json(['success' => false, 'message' => 'Citizen account is not active'], 403);
            }
            $user->forceFill([
                'mobile' => $mobile,
                'phone_verified_at' => $user->phone_verified_at ?? now(),
            ])->save();
        }

        CitizenProfile::query()->updateOrCreate(
            ['user_id' => $user->id],
            [
                'full_name' => $user->name,
                'mobile' => $mobile,
                'email' => $user->email,
                'registration_source' => 'mobile_app',
                'registered_at' => $user->created_at ?? now(),
                'last_login_at' => now(),
            ],
        );

        $token = $user->createToken('citizen-mobile')->plainTextToken;

        return response()->json([
            'success' => true,
            'message' => 'OTP verified. Login successful.',
            'token' => $token,
            'user' => $user,
        ]);
    }

    public function login(Request $request)
    {
        $request->validate([
            'username' => ['required', 'string'],
            'password' => ['required', 'string'],
        ]);

        $login = trim((string) $request->input('username'));

        // Surveyors often type Emp ID (SUR-…), mobile, or email; username is usually the mobile.
        $user = User::query()
            ->where('username', $login)
            ->orWhere('employee_id', $login)
            ->orWhere('mobile', $login)
            ->orWhere('email', $login)
            ->first();

        if (! $user || ! Hash::check($request->input('password'), $user->password)) {
            return response()->json(['success' => false, 'message' => 'Invalid credentials'], 401);
        }

        if ($user->registration_status === 'rejected') {
            return response()->json(['success' => false, 'message' => "Registration rejected: {$user->rejection_reason}"], 403);
        }

        if ($user->registration_status !== 'active') {
            return response()->json(['success' => false, 'message' => 'Your registration is still being processed'], 403);
        }

        if (! $user->is_active) {
            return response()->json(['success' => false, 'message' => 'Account is disabled'], 403);
        }

        $token = $user->createToken('auth')->plainTextToken;
        $user->load(['department', 'departments', 'district']);

        return response()->json([
            'success' => true,
            'message' => 'Login successful',
            'token' => $token,
            'user' => $user,
        ]);
    }

    public function me(Request $request)
    {
        $user = $request->user()->load(['department', 'departments', 'district']);

        return response()->json(['success' => true, 'user' => $user]);
    }

    public function changePassword(Request $request)
    {
        $request->validate([
            'current_password' => ['required', 'string'],
            'new_password' => ['required', 'string', 'min:8', 'confirmed'],
        ]);

        $user = $request->user();

        if (! Hash::check($request->input('current_password'), $user->password)) {
            return response()->json(['success' => false, 'message' => 'Current password is incorrect'], 400);
        }

        $user->password = $request->input('new_password');
        $user->save();

        return response()->json(['success' => true, 'message' => 'Password changed successfully']);
    }

    public function forgotPasswordRequest(Request $request)
    {
        $request->validate(['username' => ['required', 'string']]);

        $user = User::where('username', $request->input('username'))->first();

        $response = ['success' => true, 'message' => 'If that account exists, a reset token has been issued'];

        if ($user) {
            $token = Str::random(48);

            PasswordResetToken::create([
                'user_id' => $user->id,
                'token' => $token,
                'expires_at' => now()->addMinutes(15),
                'is_used' => false,
                'created_at' => now(),
            ]);

            // No email/SMS provider is configured yet, so the only way to deliver
            // this token in development is to hand it back directly. This must
            // never happen in production - a real delivery channel is required
            // before this ships.
            if (! app()->environment('production')) {
                $response['devToken'] = $token;
            }
        }

        return response()->json($response);
    }

    public function forgotPasswordReset(Request $request)
    {
        $request->validate([
            'token' => ['required', 'string'],
            'new_password' => ['required', 'string', 'min:8', 'confirmed'],
        ]);

        $resetToken = PasswordResetToken::where('token', $request->input('token'))
            ->where('is_used', false)
            ->where('expires_at', '>', now())
            ->first();

        if (! $resetToken) {
            return response()->json(['success' => false, 'message' => 'Invalid or expired token'], 400);
        }

        $user = $resetToken->user;
        $user->password = $request->input('new_password');
        $user->save();

        $resetToken->is_used = true;
        $resetToken->save();

        return response()->json(['success' => true, 'message' => 'Password reset successfully']);
    }
}
