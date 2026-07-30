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
        // 5 attempts / 5 minutes, keyed by IP + the submitted username - prevents
        // brute-forcing a single account without penalizing the whole IP for
        // unrelated traffic.
        RateLimiter::for('login', function ($request) {
            return Limit::perMinutes(5, 5)->by($request->ip().'|'.$request->input('username'));
        });

        RateLimiter::for('forgot-password', function ($request) {
            return Limit::perMinutes(5, 5)->by($request->ip().'|'.$request->input('username'));
        });
    }
}
