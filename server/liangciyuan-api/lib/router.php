<?php
declare(strict_types=1);

final class Router
{
    private array $routes = [];

    public function add(string $method, string $pattern, callable|string $handler): void
    {
        $this->routes[] = [$method, $pattern, $handler];
    }

    public function dispatch(Request $request): void
    {
        header('Access-Control-Allow-Origin: *');
        header('Access-Control-Allow-Headers: Authorization, Content-Type');
        header('Access-Control-Allow-Methods: GET, POST, PATCH, PUT, DELETE, OPTIONS');
        if ($request->method === 'OPTIONS') {
            http_response_code(204);
            exit;
        }

        $allowed = [];
        foreach ($this->routes as [$method, $pattern, $handler]) {
            [$matched, $params] = $this->match($pattern, $request->path);
            if (!$matched) {
                continue;
            }
            if ($method !== $request->method) {
                $allowed[] = $method;
                continue;
            }
            $request->params = $params;
            try {
                $handler($request);
                return;
            } catch (HttpException $e) {
                Response::error($e->status, $e->getMessage());
            } catch (Throwable $e) {
                error_log('liangciyuan api: ' . $e->getMessage());
                Response::error(500, '服务器内部错误');
            }
        }

        if ($allowed !== []) {
            Response::error(405, '请求方法不被允许');
        }
        Response::error(404, '接口不存在');
    }

    private function match(string $pattern, string $path): array
    {
        $names = [];
        $regex = preg_replace_callback(
            '/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/',
            static function (array $m) use (&$names): string {
                $names[] = $m[1];
                return '([^/]+)';
            },
            $pattern
        );
        if (!preg_match('#^' . $regex . '$#', $path, $matches)) {
            return [false, []];
        }
        array_shift($matches);
        $params = [];
        foreach ($names as $index => $name) {
            $params[$name] = $matches[$index] ?? '';
        }
        return [true, $params];
    }
}