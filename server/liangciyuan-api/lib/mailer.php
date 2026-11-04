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
            $body = chunk_split(base64_encode($html), 76, "\r\n");
            $data = "From: {$encodedFrom} <{$user}>\r\n"
                . "To: <{$toEmail}>\r\n"
                . "Subject: {$encodedSubject}\r\n"
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
    return '<div style="font-family:sans-serif;line-height:1.7;color:#222">'
        . '<h2 style="margin:0 0 12px">凉次元注册验证码</h2>'
        . '<p>你的验证码是：</p>'
        . '<p style="font-size:28px;letter-spacing:6px;font-weight:700">' . htmlspecialchars($code) . '</p>'
        . '<p>10 分钟内有效，请勿转发给他人。</p>'
        . '<p style="color:#888;font-size:12px">如果这不是你本人操作，请忽略本邮件。</p>'
        . '</div>';
}