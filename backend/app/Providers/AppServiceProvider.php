<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Local: generous so repeated manual testing isn't blocked.
        // Production keeps the tight 5 / 5-minute window.
        RateLimiter::for('login', function ($request) {
            $key = $request->ip().'|'.$request->input('username');
            if (app()->environment('local')) {
                return Limit::perMinute(60)->by($key);
            }

            return Limit::perMinutes(5, 5)->by($key);
        });

        RateLimiter::for('forgot-password', function ($request) {
            $key = $request->ip().'|'.$request->input('username');
            if (app()->environment('local')) {
                return Limit::perMinute(30)->by($key);
            }

            return Limit::perMinutes(5, 5)->by($key);
        });

        RateLimiter::for('otp-send', function ($request) {
            $key = $request->ip().'|'.$request->input('mobile');
            if (app()->environment('local')) {
                return Limit::perMinute(60)->by($key);
            }

            return Limit::perMinutes(10, 5)->by($key);
        });

        RateLimiter::for('otp-verify', function ($request) {
            $key = $request->ip().'|'.$request->input('mobile');
            if (app()->environment('local')) {
                return Limit::perMinute(120)->by($key);
            }

            return Limit::perMinutes(10, 10)->by($key);
        });
    }
}
