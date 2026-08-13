<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Requires `php artisan schedule:run` to fire every minute via system cron -
// not yet configured anywhere in this repo/deployment.
Schedule::command('complaints:escalate-overdue')->everyFifteenMinutes();
Schedule::command('complaints:auto-close-resolved')->daily();
