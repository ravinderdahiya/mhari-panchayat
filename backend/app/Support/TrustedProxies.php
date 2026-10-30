<?php

namespace App\Support;

/** Reads the TRUSTED_PROXIES env value ('*' or "10.0.0.1, 192.168.1.0/24") for Laravel's trustProxies(). */
class TrustedProxies
{
    /** @return string|list<string>|null null = trust nobody (the safe default) */
    public static function fromEnv(mixed $value): string|array|null
    {
        $value = is_string($value) ? trim($value) : '';
        if ($value === '') {
            return null;
        }
        if ($value === '*') {
            return '*';
        }

        $addresses = array_values(array_filter(array_map('trim', explode(',', $value)), fn ($a) => $a !== ''));

        return $addresses === [] ? null : $addresses;
    }
}
