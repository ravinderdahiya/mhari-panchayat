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

    // Demo login for Play Store / App Store reviewers, who cannot receive an SMS:
    // exactly this one mobile number signs in with exactly this OTP. Unset either
    // value to switch it off. Unlike otp_bypass above it works for no other number.
    'otp_demo' => [
        'mobile' => env('OTP_DEMO_MOBILE'),
        'code' => env('OTP_DEMO_CODE'),
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

    // Separate ArcGIS Enterprise portal (hsac.org.in, not gis.harsac.in) - hosts the
    // EODB_HR24 MapServer being tried as a test/replacement boundary source. Its own
    // portal means its own account and token, not interchangeable with harsac_gis above.
    'hsac_eodb' => [
        'username' => env('HSAC_USERNAME'),
        'password' => env('HSAC_PASSWORD'),
        'token_url' => env('HSAC_TOKEN_GENERATE_URL', 'https://hsac.org.in/portal/sharing/rest/generateToken'),
        'referer' => env('HSAC_TOKEN_REFERER', 'https://hsac.in'),
        'token_ttl_minutes' => (int) env('HSAC_TOKEN_EXPIRATION_MINUTES', 60),
    ],

    // Firebase Cloud Messaging (push notifications). Path to the service-account JSON
    // downloaded from Firebase console > Project settings > Service accounts.
    // Unset = push is skipped and only the in-app inbox is used.
    'firebase' => [
        'credentials' => env('FIREBASE_CREDENTIALS'),
        'ca_bundle' => env('FIREBASE_CA_BUNDLE'),
    ],

];
