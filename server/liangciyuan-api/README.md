# 凉次元账号 / 云同步服务（PHP，无 Composer）

部署在虚拟主机子目录（例如 `/liangciyuan/`），与站点根目录的现有应用互不影响。

## 目录

```
api.php              入口（用 /api.php/v1/... 访问，无需 URL 重写）
lib/                 配置、路由、SQLite、SMTP、鉴权、接口实现
config.example.php   配置模板；复制为 config.local.php 后填 QQ 邮箱与授权码
```

运行数据写入站点根目录的 `data/`（`liangciyuan.sqlite`、`liangciyuan-avatars/`），
该目录已被根站伪静态规则禁止直接访问。

## 部署

```powershell
# 1) 打包（zip 根目录直接是 api.php）
Compress-Archive -Path server\liangciyuan-api\* -DestinationPath server\liangciyuan-api.zip -Force

# 2) 上传并解压
powershell -File "C:\Users\Administrator\.zcode\skills\hk-vhost\scripts\mnbt.ps1" deploy server\liangciyuan-api.zip -To /liangciyuan

# 3) 写入本地配置（含邮箱授权码，切勿提交）
```

`config.local.php`（在 `/liangciyuan/` 下）示例：

```php
<?php
return [
    'mail_user' => '123456789@qq.com',
    'mail_auth' => 'QQ 邮箱 SMTP 授权码',
    'mail_from_name' => '凉次元',
];
```

## 接口

Base：`https://<域名>/liangciyuan/api.php`

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/v1/ping` | 健康检查 |
| POST | `/v1/auth/send-code` | `{email, purpose=register\|reset}`，仅 QQ 邮箱，发送 6 位验证码 |
| POST | `/v1/auth/register` | `{email, code, password, nickname}`，返回 token |
| POST | `/v1/auth/reset` | `{email, code, password}`，重置密码并吊销全部令牌 |
| POST | `/v1/auth/login` | `{email, password}`，返回 token |
| POST | `/v1/auth/logout` | 注销当前 token |
| GET | `/v1/me` | 当前用户资料 |
| PATCH | `/v1/me` | `{nickname}` 修改昵称 |
| POST | `/v1/me/avatar` | multipart `avatar`（JPG/PNG/WebP ≤ 2MB） |
| GET | `/v1/avatar/{id}` | 头像文件 |
| GET | `/v1/sync` | 列出已同步的类型 |
| GET | `/v1/sync/{kind}` | 读取 `{payload(base64), updatedAt, checksum}` |
| PUT | `/v1/sync/{kind}` | `{payload(base64), updatedAt}`，服务端按 updatedAt 做后写优先 |
| DELETE | `/v1/sync/{kind}` | 删除某一类同步数据 |
| GET | `/v1/comments` | `?targetType=bangumi&targetId=&offset=&limit=`，未登录可读，返回 `{total, items}` |
| POST | `/v1/comments` | `{targetType, targetId, content, spoiler}`，登录后发布吐槽（≤500 字） |
| DELETE | `/v1/comments/{id}` | 删除自己的吐槽（软删除） |

鉴权：`Authorization: Bearer <token>`。

同步类型约定（客户端）：`collectibles`、`collectchanges`。
后续历史记录/弹幕屏蔽词可复用同一接口，新增 kind 即可。

## 安全

- 密码 bcrypt；token 仅存 sha256 摘要，有效期 180 天。
- 验证码 6 位、10 分钟过期、一次性，60 秒内不可重发，单 IP 每小时 20 次。
- 头像校验真实图片类型与大小，文件名由服务端生成。
- 单次同步 payload 上限 8 MB（base64 解码后）。
- 吐槽按用户限流（10 条/5 分钟），软删除不物理清除。