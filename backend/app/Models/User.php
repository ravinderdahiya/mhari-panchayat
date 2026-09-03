<?php

namespace App\Models;

use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\HasApiTokens;
use Throwable;

#[Fillable([
    'username', 'name', 'email', 'password', 'role', 'is_active', 'department_id',
    'district_id', 'block_id', 'panchayat_id', 'employee_id', 'member_id', 'family_id', 'mobile', 'registration_status',
    'email_verified_at', 'phone_verified_at',
    'email_verification_token', 'email_verification_expires_at',
    'set_password_token', 'set_password_token_expires_at',
    'rejection_reason', 'reviewed_by_id', 'reviewed_at',
])]
#[Hidden(['password', 'login_password_enc', 'email_verification_token', 'set_password_token'])]
class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, Notifiable;

    protected function casts(): array
    {
        return [
            'password' => 'hashed',
            'is_active' => 'boolean',
            'email_verified_at' => 'datetime',
            'phone_verified_at' => 'datetime',
            'email_verification_expires_at' => 'datetime',
            'set_password_token_expires_at' => 'datetime',
            'reviewed_at' => 'datetime',
        ];
    }

    public function setAttribute($key, $value)
    {
        if ($key === 'password' && is_string($value) && $value !== '' && ! Hash::isHashed($value)) {
            parent::setAttribute('login_password_enc', Crypt::encryptString($value));
        }

        return parent::setAttribute($key, $value);
    }

    /** Plain login password for the admin Users table. Null when it was never captured (bcrypt cannot be reversed). */
    public function revealedLoginPassword(): ?string
    {
        $blob = $this->attributes['login_password_enc'] ?? null;
        if (! is_string($blob) || $blob === '') {
            return null;
        }

        try {
            return Crypt::decryptString($blob);
        } catch (Throwable) {
            return null;
        }
    }

    protected function loginPassword(): Attribute
    {
        return Attribute::get(fn (): ?string => $this->revealedLoginPassword());
    }

    public function appendRevealedLoginPassword(): static
    {
        return $this->append('login_password');
    }

    public function complaints(): HasMany
    {
        return $this->hasMany(Complaint::class);
    }

    public function citizenProfile(): HasOne
    {
        return $this->hasOne(CitizenProfile::class);
    }

    public function assetSurveys(): HasMany
    {
        return $this->hasMany(AssetSurvey::class, 'surveyor_id');
    }

    public function assignedComplaints(): HasMany
    {
        return $this->hasMany(Complaint::class, 'assigned_to_id');
    }

    public function department(): BelongsTo
    {
        return $this->belongsTo(Department::class);
    }

    /** Multi-department assignment (survey work scope). */
    public function departments(): BelongsToMany
    {
        return $this->belongsToMany(Department::class)->withTimestamps();
    }

    /** Multi-village assignment (survey coverage area). */
    public function villages(): BelongsToMany
    {
        return $this->belongsToMany(Village::class, 'user_villages')->withTimestamps();
    }

    public function district(): BelongsTo
    {
        return $this->belongsTo(District::class);
    }

    public function block(): BelongsTo
    {
        return $this->belongsTo(Block::class);
    }

    /** Multi-block coverage (a BDPO holding "additional charge" of other blocks). */
    public function blocks(): BelongsToMany
    {
        return $this->belongsToMany(Block::class, 'user_blocks')->withTimestamps();
    }

    public function panchayat(): BelongsTo
    {
        return $this->belongsTo(Panchayat::class);
    }

    public function reviewedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by_id');
    }

    public function isSuperAdmin(): bool
    {
        return Role::isSuperAdmin($this->role);
    }

    /** @return list<string> */
    public function permissionKeys(): array
    {
        if ($this->isSuperAdmin()) {
            return Permission::orderBy('key')->pluck('key')->all();
        }

        return RolePermission::query()
            ->where('role', $this->role)
            ->with('permission:id,key')
            ->get()
            ->pluck('permission.key')
            ->filter()
            ->values()
            ->all();
    }

    public function hasPermission(string $key): bool
    {
        return $this->isSuperAdmin() || in_array($key, $this->permissionKeys(), true);
    }

    /** @return array<string, mixed> */
    public function toAuthArray(): array
    {
        $data = $this->toArray();
        unset($data['login_password'], $data['login_password_enc']);
        $data['is_super_admin'] = $this->isSuperAdmin();
        $data['permissions'] = $this->permissionKeys();

        return $data;
    }
}
