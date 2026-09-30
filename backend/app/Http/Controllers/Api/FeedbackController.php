<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Feedback;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

// In-app feedback from staff (mobile app) - free-text + optional rating,
// category and a screenshot/photo. Anyone authenticated can submit; only
// permission:feedback.view holders (admin/state_admin/super_admin by
// default - see PermissionSeeder) can read the list.
class FeedbackController extends Controller
{
    private const CATEGORIES = ['bug', 'suggestion', 'complaint', 'general'];

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'message' => ['required', 'string', 'max:2000'],
            'rating' => ['nullable', 'integer', 'between:1,5'],
            'category' => ['required', 'in:'.implode(',', self::CATEGORIES)],
            'photo' => ['nullable', 'file', 'image', 'max:10240'],
        ]);

        $user = $request->user();
        $photoPath = $request->hasFile('photo')
            ? $request->file('photo')->store('feedback/photos', 'public')
            : null;

        $feedback = Feedback::create([
            'user_id' => $user->id,
            'user_role' => $user->role,
            'category' => $data['category'],
            'rating' => $data['rating'] ?? null,
            'message' => $data['message'],
            'photo_path' => $photoPath,
        ]);

        return response()->json(['success' => true, 'feedback' => $this->mapFeedback($feedback)], 201);
    }

    public function index(): JsonResponse
    {
        $feedback = Feedback::with('user:id,name,username,role')
            ->orderByDesc('created_at')
            ->get()
            ->map(fn (Feedback $item) => $this->mapFeedback($item))
            ->values();

        return response()->json(['success' => true, 'feedback' => $feedback]);
    }

    private function photoUrl(string $path): string
    {
        return rtrim(config('app.url'), '/').'/storage/'.ltrim($path, '/');
    }

    private function mapFeedback(Feedback $feedback): array
    {
        $submitterName = $feedback->user?->name ?: $feedback->user?->username;

        return [
            'id' => $feedback->id,
            'category' => $feedback->category,
            'rating' => $feedback->rating,
            'message' => $feedback->message,
            'photoUrl' => $feedback->photo_path ? $this->photoUrl($feedback->photo_path) : null,
            'userId' => $feedback->user_id,
            'userName' => $submitterName,
            'userRole' => $feedback->user_role,
            'createdAt' => $feedback->created_at?->toISOString(),
        ];
    }
}
