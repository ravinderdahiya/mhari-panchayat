<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

// Synchronous send (no ShouldQueue) - no queue worker process is confirmed
// running locally (QUEUE_CONNECTION=database with no `queue:work`/`queue:listen`
// running), so queuing this would leave it stuck unprocessed in the `jobs`
// table. Revisit if/when a worker is deployed.
class RegistrationVerificationMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(public string $token, public string $email)
    {
    }

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: 'Verify your email - Mhari Panchayat',
        );
    }

    public function content(): Content
    {
        // Prefer APP_PUBLIC_URL (phone-reachable host) over APP_URL. Gmail /
        // Outlook block custom schemes in buttons, so the CTA must be https
        // (or http on LAN). The verify-link page then opens the app — same
        // pattern as basmati-survey-app's mailer.
        $publicBase = rtrim((string) (env('APP_PUBLIC_URL') ?: config('app.url')), '/');
        $webLink = $publicBase.'/api/registrations/email/verify-link'
            .'?token='.rawurlencode($this->token)
            .'&email='.rawurlencode($this->email);

        return new Content(
            view: 'emails.registration-verification',
            with: [
                'token' => $this->token,
                'webLink' => $webLink,
                // Kept for older clients / manual testing; not used as the CTA.
                'deepLink' => 'mharipanchayat://verify-email?token='.rawurlencode($this->token)
                    .'&email='.rawurlencode($this->email),
            ],
        );
    }
}
