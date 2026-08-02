<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Verify your email</title>
</head>
<body style="font-family: -apple-system, Arial, sans-serif; background:#f5f5f5; padding:24px;">
    <table role="presentation" width="100%" style="max-width:480px;margin:0 auto;background:#ffffff;border-radius:12px;padding:32px;">
        <tr>
            <td>
                <h2 style="margin:0 0 16px;color:#0D3D2F;">Mhari Panchayat</h2>
                <p style="margin:0 0 16px;color:#333;font-size:15px;line-height:1.45;">
                    Please verify your email for the Mhari Panchayat app. After you verify, the app will open so you can set your password.
                </p>
                <div style="margin:0 0 20px;text-align:center;">
                    <a href="{{ $webLink }}"
                       style="display:inline-block;padding:14px 28px;background:#0D3D2F;color:#ffffff !important;text-decoration:none;border-radius:10px;font-weight:700;font-size:15px;"
                       target="_blank" rel="noopener">
                        Verify email &amp; open app
                    </a>
                </div>
                <p style="margin:0 0 8px;color:#777;font-size:13px;">
                    Or copy this link into your phone browser:
                </p>
                <p style="margin:0 0 20px;word-break:break-all;font-size:13px;">
                    <a href="{{ $webLink }}" style="color:#1B5C45;">{{ $webLink }}</a>
                </p>
                <p style="margin:0;color:#777;font-size:13px;">
                    This link expires in 24 hours. An administrator must still approve your account before you can sign in.
                </p>
            </td>
        </tr>
    </table>
</body>
</html>
