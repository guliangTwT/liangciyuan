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
        echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
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