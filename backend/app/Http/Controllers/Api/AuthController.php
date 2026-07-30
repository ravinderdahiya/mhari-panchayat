<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PasswordResetToken;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class AuthController extends Controller
{
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

    public function login(Request $request)
    {
        $request->validate([
            'username' => ['required', 'string'],
            'password' => ['required', 'string'],
        ]);

        $user = User::where('username', $request->input('username'))->first();

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

        return response()->json([
            'success' => true,
            'message' => 'Login successful',
            'token' => $token,
            'user' => $user,
        ]);
    }

    public function me(Request $request)
    {
        return response()->json(['success' => true, 'user' => $request->user()]);
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
