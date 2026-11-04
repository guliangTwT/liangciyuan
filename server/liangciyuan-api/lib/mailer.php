<?php
declare(strict_types=1);

final class SmtpMailer
{
    public static function send(string $toEmail, string $subject, string $html): void
    {
        $config = app_config();
        $user = trim((string) $config['mail_user']);
        $auth = trim((string) $config['mail_auth']);
        if ($user === '' || $auth === '') {
            throw new HttpException(503, '服务端未配置发件邮箱');
        }

        $fp = @stream_socket_client(
            $config['mail_host'] . ':' . $config['mail_port'],
            $errno,
            $errstr,
            15,
            STREAM_CLIENT_CONNECT
        );
        if (!is_resource($fp)) {
            throw new HttpException(502, '无法连接邮件服务器：' . $errstr);
        }
        stream_set_timeout($fp, 15);

        try {
            self::expect($fp, [220]);
            self::command($fp, 'EHLO liangciyuan', [250]);
            self::command($fp, 'AUTH LOGIN', [334]);
            self::command($fp, base64_encode($user), [334]);
            self::command($fp, base64_encode($auth), [235]);
            self::command($fp, 'MAIL FROM:<' . $user . '>', [250]);
            self::command($fp, 'RCPT TO:<' . $toEmail . '>', [250, 251]);
            self::command($fp, 'DATA', [354]);

            $encodedSubject = '=?UTF-8?B?' . base64_encode($subject) . '?=';
            $encodedFrom = '=?UTF-8?B?' . base64_encode((string) $config['mail_from_name']) . '?=';
            $domain = substr((string) strrchr($user, '@'), 1) ?: 'localhost';
            $messageId = '<' . bin2hex(random_bytes(16)) . '@' . $domain . '>';
            $body = chunk_split(base64_encode($html), 76, "\r\n");
            $data = "From: {$encodedFrom} <{$user}>\r\n"
                . "To: <{$toEmail}>\r\n"
                . "Subject: {$encodedSubject}\r\n"
                . "Message-ID: {$messageId}\r\n"
                . "X-Mailer: Liangciyuan\r\n"
                . "MIME-Version: 1.0\r\n"
                . "Content-Type: text/html; charset=UTF-8\r\n"
                . "Content-Transfer-Encoding: base64\r\n"
                . "Date: " . date('r') . "\r\n"
                . "\r\n"
                . $body
                . ".\r\n";
            fwrite($fp, $data);
            self::expect($fp, [250]);
            self::command($fp, 'QUIT', [221]);
        } finally {
            @fclose($fp);
        }
    }

    private static function command($fp, string $command, array $codes): string
    {
        fwrite($fp, $command . "\r\n");
        return self::expect($fp, $codes);
    }

    private static function expect($fp, array $codes): string
    {
        $data = '';
        while (($line = fgets($fp, 1024)) !== false) {
            $data .= $line;
            if (strlen($line) >= 4 && $line[3] === ' ') {
                break;
            }
        }
        if ($data === '') {
            throw new HttpException(502, '邮件服务器无响应');
        }
        $code = (int) substr($data, 0, 3);
        if (!in_array($code, $codes, true)) {
            throw new HttpException(502, '邮件服务器返回错误：' . trim($data));
        }
        return $data;
    }
}

function verification_mail_html(string $code): string
{
    $safe = htmlspecialchars($code, ENT_QUOTES, 'UTF-8');
    $year = date('Y');
    $font = "-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei',sans-serif";

    return '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8">'
        . '<meta name="viewport" content="width=device-width,initial-scale=1"></head>'
        . '<body style="margin:0;padding:0;background:#f4f3f8;">'
        . '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" '
        . 'style="background:#f4f3f8;padding:32px 12px;"><tr><td align="center">'
        . '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" '
        . 'style="max-width:540px;background:#ffffff;border-radius:18px;border:1px solid #ece8f5;">'
        // 头部
        . '<tr><td style="background:#1a1520;padding:28px 32px;border-radius:18px 18px 0 0;">'
        . '<div style="font-family:' . $font . ';font-size:22px;font-weight:700;'
        . 'color:#ffffff;letter-spacing:3px;">凉次元</div>'
        . '<div style="font-family:' . $font . ';margin-top:6px;font-size:11px;'
        . 'color:#a99fc0;letter-spacing:2px;">LIANGCIYUAN ACCOUNT</div>'
        . '</td></tr>'
        // 正文
        . '<tr><td style="padding:34px 32px 8px;">'
        . '<div style="font-family:' . $font . ';font-size:18px;font-weight:600;color:#1f1a26;">'
        . '验证你的邮箱</div>'
        . '<div style="font-family:' . $font . ';margin-top:12px;font-size:14px;'
        . 'line-height:1.8;color:#6b6575;">你好，你正在注册凉次元账号。'
        . '请在应用内输入下面的验证码完成验证：</div>'
        . '<div style="margin:26px 0;padding:22px 12px;text-align:center;'
        . 'background:#f7f4fb;border:1px dashed #d9cfea;border-radius:14px;">'
        . '<span style="font-family:' . $font . ';display:inline-block;font-size:34px;'
        . 'line-height:1;font-weight:700;letter-spacing:10px;color:#1a1520;'
        . 'padding-left:10px;">' . $safe . '</span></div>'
        . '<div style="font-family:' . $font . ';font-size:13px;line-height:1.8;color:#6b6575;">'
        . '验证码 <strong style="color:#1f1a26;">10 分钟内有效</strong>，请勿转发给他人。</div>'
        . '</td></tr>'
        . '<tr><td style="padding:22px 32px 0;">'
        . '<div style="height:1px;background:#f0edf6;"></div></td></tr>'
        // 页脚
        . '<tr><td style="padding:18px 32px 28px;border-radius:0 0 18px 18px;">'
        . '<div style="font-family:' . $font . ';font-size:12px;line-height:1.8;color:#9a94a6;">'
        . '如果这不是你本人操作，请忽略本邮件，该邮箱不会被注册。</div>'
        . '<div style="font-family:' . $font . ';margin-top:6px;font-size:12px;color:#9a94a6;">'
        . '此邮件由系统自动发送，请勿直接回复。</div>'
        . '</td></tr></table>'
        . '<div style="font-family:' . $font . ';margin-top:16px;font-size:11px;color:#b3adc0;">'
        . '© ' . $year . ' 凉次元</div>'
        . '</td></tr></table></body></html>';
}