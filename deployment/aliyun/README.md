# 阿里云试用部署

完整试用边界见 [安卓试用说明](../../docs/deployment/aliyun-android-pilot.md)。保留既有服务器项目、卷、密钥、环境文件；不能直接将开发配置暴露公网。

在已有生产及资源配置后应用 `docker-compose.https-ip.yml`。需要固定公网 IPv4、80/443 可达、Certbot >=5.4、证书目录及 webroot。首次使用 ACME HTTP-only 临时 nginx，先完成正式证书签发，核验 IP SAN 与有效期，再切换 HTTPS 网关：

```bash
sudo /opt/pig-inventory-certbot/bin/certbot certonly --webroot \
  -w /var/lib/pig-inventory-acme --preferred-profile shortlived \
  --ip-address '<固定公网IPv4>' --cert-name pig-inventory-ip
sudo openssl x509 -in /etc/letsencrypt/live/pig-inventory-ip/fullchain.pem -noout -checkend 86400
```

证书文件尚未存在时不能启动依赖证书的 HTTPS nginx，更不能用 staging 证书代替正式证书。证书及私钥不进入 Git。

核对 service 中的 Compose 容器名后，将这里的 service/timer 安装到 `/etc/systemd/system/`，执行 `systemctl daemon-reload`、`systemctl enable --now pig-inventory-cert-renew.timer`。在外网 HTTPS 已可用时执行以下命令，并要求续期与 deploy-hook 均成功：

```bash
sudo /opt/pig-inventory-certbot/bin/certbot renew --cert-name pig-inventory-ip --dry-run --run-deploy-hooks
sudo systemctl list-timers pig-inventory-cert-renew.timer
```

下载目录 `artifacts/pilot-downloads` 只能放经签名验证的 APK 及公开 SHA-256；不放凭据、私钥、日志或原始媒体。网关仅允许精确列出的下载文件，其他 `/downloads/` 请求返回 404。模板中的版本化下载文件名随下一版显式更新。

官方依据：[IP 与六天证书](https://letsencrypt.org/2026/01/15/6day-and-ip-general-availability/)、[Certbot 短期证书支持](https://letsencrypt.org/2026/03/11/shorter-certs-certbot)。首次签发成功不替代持续续期。
