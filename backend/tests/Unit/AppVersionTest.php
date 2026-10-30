<?php

namespace Tests\Unit;

use App\Models\AppVersion;
use PHPUnit\Framework\TestCase;

class AppVersionTest extends TestCase
{
    private function version(int $latest, int $min): AppVersion
    {
        return new AppVersion(['latest_version_code' => $latest, 'min_version_code' => $min]);
    }

    public function test_build_below_minimum_is_forced_to_update(): void
    {
        $this->assertSame('force_update', $this->version(5, 3)->statusFor(2));
    }

    public function test_build_between_minimum_and_latest_gets_an_optional_prompt(): void
    {
        $version = $this->version(5, 3);

        $this->assertSame('optional_update', $version->statusFor(3));
        $this->assertSame('optional_update', $version->statusFor(4));
    }

    public function test_latest_or_newer_build_is_ok(): void
    {
        $version = $this->version(5, 3);

        $this->assertSame('ok', $version->statusFor(5));
        $this->assertSame('ok', $version->statusFor(9));
    }

    public function test_minimum_equal_to_latest_forces_every_older_build(): void
    {
        $version = $this->version(3, 3);

        $this->assertSame('force_update', $version->statusFor(2));
        $this->assertSame('ok', $version->statusFor(3));
    }
}
