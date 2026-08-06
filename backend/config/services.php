<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    'pixabits' => [
        'url' => env('SMS_API_URL', 'https://sms.pixabits.in/smsapi/sms/custom/send'),
        'api_key' => env('SMS_API_KEY'),
        'sender_id' => env('SMS_SENDER_ID'),
        'dlt_id' => env('SMS_TEMP_DLT_ID'),
        'route' => env('SMS_ROUTE', 'Domestic'),
    ],

    // Temporary stopgap while SMS delivery is broken on live. Unset OTP_STATIC_BYPASS_CODE
    // (and run `php artisan config:clear`) as soon as the SMS provider is fixed.
    'otp_bypass' => [
        'code' => env('OTP_STATIC_BYPASS_CODE'),
    ],

    // HARSAC's ArcGIS Enterprise portal - hosts the Panchayat boundary MapServer.
    // Token-secured, so the admin panel can't call it directly with a username/password;
    // it asks the backend for a short-lived, referer-locked token instead.
    'harsac_gis' => [
        'username' => env('GIS_HARSAC_USERNAME'),
        'password' => env('GIS_HARSAC_PASSWORD'),
        'token_url' => env('GIS_HARSAC_TOKEN_URL', 'https://gis.harsac.in/portal/sharing/rest/generateToken'),
        'referer' => env('GIS_HARSAC_REFERER', 'https://hsac.in'),
    ],

];
