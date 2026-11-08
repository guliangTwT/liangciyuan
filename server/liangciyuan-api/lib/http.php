<?php
declare(strict_types=1);

final class HttpException extends Exception
{
    public int $status;

    public function __construct(int $status, string $message)
    {
        parent::__construct($message);
        $this->status = $status;
    }
}

final class Request
{
    public string $method;
    public string $path;
    public array $query;
    public array $params = [];

    public static function fromGlobals(): self
    {
        $self = new self();
        $self->method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        $path = $_SERVER['PATH_INFO'] ?? '';
        if ($path === '') {
            $uri = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
            $script = rtrim(dirname($_SERVER['SCRIPT_NAME'] ?? '/'), '/');
            if ($script !== '' && strpos($uri, $script) === 0) {
                $uri = substr($uri, strlen($script));
            }
            $path = $uri;
        }
        $path = '/' . trim($path, '/');
        $self->path = $path === '/' ? '/' : rtrim($path, '/');
        $self->query = $_GET ?? [];
        return $self;
    }

    public function header(string $name): string
    {
        $key = 'HTTP_' . strtoupper(str_replace('-', '_', $name));
        return trim((string) ($_SERVER[$key] ?? ''));
    }

    public function json(): array
    {
        $raw = file_get_contents('php://input');
        if ($raw === false || $raw === '') {
            return [];
        }
        $data = json_decode($raw, true);
        if (!is_array($data)) {
            throw new HttpException(400, '请求体不是合法 JSON');
        }
        return $data;
    }

    public function bearerToken(): string
    {
        $header = $this->header('Authorization');
        if ($header !== '' && stripos($header, 'Bearer ') === 0) {
            return trim(substr($header, 7));
        }
        return '';
    }
}

final class Response
{
    public static function json(array $data, int $status = 200): void
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        header('X-Content-Type-Options: nosniff');
        header('Cache-Control: no-store');
        // 库里万一存了非法 UTF-8（历史脏数据），json_encode 会返回 false，
        // 页面变成空 body 却仍是 200，客户端只会报「无法识别的数据」。
        // 用 SUBSTITUTE 保证至少是合法 JSON，坏字节替换成 U+FFFD。
        $encoded = json_encode(
            $data,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE
        );
        if ($encoded === false) {
            http_response_code(500);
            echo '{"ok":false,"error":"服务器内部错误"}';
            exit;
        }
        echo $encoded;
        exit;
    }

    public static function ok(array $data = []): void
    {
        self::json(['ok' => true] + $data);
    }

    public static function error(int $status, string $message): void
    {
        self::json(['ok' => false, 'error' => $message], $status);
    }
}

function now(): int
{
    return time();
}