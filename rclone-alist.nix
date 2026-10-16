# OpenList WebDAV → /mnt/alist 的 rclone 挂载
# 结构 = /mnt/alist/<云盘名>（阿里云盘、以后加的各种云盘都自动出现在这里）
# 凭据在 /etc/rclone/rclone.conf（手工创建、600、obscured 密码；不进 nix store）
# 回滚：把 configuration.nix imports 里的 ./rclone-alist.nix 删掉 → rebuild
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.rclone ];

  systemd.tmpfiles.rules = [ "d /mnt/alist 0755 root root -" ];

  systemd.services.rclone-alist = {
    description = "rclone mount OpenList WebDAV -> /mnt/alist";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "notify";
      ExecStartPre = "-${pkgs.fuse3}/bin/fusermount3 -u /mnt/alist";
      ExecStart = "${pkgs.rclone}/bin/rclone mount alist: /mnt/alist --config /etc/rclone/rclone.conf --uid 1000 --gid 100 --umask 002 --allow-other --vfs-cache-mode writes --vfs-cache-max-age 24h --cache-dir /var/cache/rclone";
      ExecStop = "${pkgs.fuse3}/bin/fusermount3 -u /mnt/alist";
      Restart = "on-failure";
      RestartSec = "5s";
      CacheDirectory = "rclone";
      CacheDirectoryMode = "0700";
    };
  };
}
