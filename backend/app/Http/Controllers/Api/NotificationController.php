<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\UserNotification;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    public function index(Request $request)
    {
        $notifications = UserNotification::query()
            ->where('user_id', $request->user()->id)
            ->orderByDesc('created_at')
            ->limit(100)
            ->get()
            ->map(fn (UserNotification $n) => $n->toApiArray())
            ->values();

        return response()->json([
            'success' => true,
            'notifications' => $notifications,
        ]);
    }

    public function markRead(Request $request, int $id)
    {
        $notification = UserNotification::query()
            ->where('user_id', $request->user()->id)
            ->whereKey($id)
            ->first();

        if (! $notification) {
            return response()->json([
                'success' => false,
                'message' => 'Notification not found',
            ], 404);
        }

        if (! $notification->is_read) {
            $notification->update(['is_read' => true]);
        }

        return response()->json([
            'success' => true,
            'message' => 'Marked as read',
            'notification' => $notification->fresh()->toApiArray(),
        ]);
    }
}
