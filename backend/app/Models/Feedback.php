<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Feedback extends Model
{
    // Eloquent's pluralizer treats "feedback" as uncountable and would
    // otherwise guess the table name "feedback" (no s), which doesn't match
    // the migration's "feedbacks" table.
    protected $table = 'feedbacks';

    protected $fillable = ['user_id', 'user_role', 'category', 'rating', 'message', 'photo_path'];

    protected $casts = [
        'rating' => 'integer',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
