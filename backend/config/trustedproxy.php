<?php

use App\Support\TrustedProxies;

return [
    // The live reverse proxy connects over loopback. Other proxy addresses must
    // be configured explicitly; never trust forwarded IPs from arbitrary clients.
    'proxies' => TrustedProxies::fromEnv(env('TRUSTED_PROXIES', '127.0.0.1,::1')),
];
