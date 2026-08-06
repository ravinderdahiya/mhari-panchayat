<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\URL;
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
        // IIS proxies to this process via 127.0.0.1:8083 without forwarding the
        // original public Host header, so url()/asset() would otherwise generate
        // links back to that internal address instead of the public site.
        URL::forceRootUrl(config('app.url'));
        URL::forceScheme(str_starts_with(config('app.url'), 'https://') ? 'https' : 'http');

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
