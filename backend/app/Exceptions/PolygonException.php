<?php

namespace App\Exceptions;

use RuntimeException;

// A track that can't be turned into a usable polygon (too few points, zero
// area, uuid owned by someone else...). Rendered as an API error envelope.
class PolygonException extends RuntimeException
{
    /** @param array<string, array<int, string>> $errors */
    public function __construct(
        string $message,
        public readonly array $errors = [],
        public readonly int $status = 422,
    ) {
        parent::__construct($message);
    }
}
