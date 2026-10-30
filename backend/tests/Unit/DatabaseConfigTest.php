<?php

namespace Tests\Unit;

use PDO;
use Tests\TestCase;

class DatabaseConfigTest extends TestCase
{
    private function pgsqlOptions(?string $persistent): array
    {
        if ($persistent === null) {
            unset($_ENV['DB_PERSISTENT'], $_SERVER['DB_PERSISTENT']);
        } else {
            $_ENV['DB_PERSISTENT'] = $_SERVER['DB_PERSISTENT'] = $persistent;
        }

        return (require config_path('database.php'))['connections']['pgsql']['options'];
    }

    protected function tearDown(): void
    {
        unset($_ENV['DB_PERSISTENT'], $_SERVER['DB_PERSISTENT']);
        parent::tearDown();
    }

    public function test_persistent_connections_are_off_unless_asked_for(): void
    {
        $this->assertSame([], $this->pgsqlOptions(null));
        $this->assertSame([], $this->pgsqlOptions('false'));
    }

    public function test_db_persistent_true_keeps_the_connection_between_requests(): void
    {
        $this->assertSame([PDO::ATTR_PERSISTENT => true], $this->pgsqlOptions('true'));
        $this->assertSame([PDO::ATTR_PERSISTENT => true], $this->pgsqlOptions('1'));
    }
}
