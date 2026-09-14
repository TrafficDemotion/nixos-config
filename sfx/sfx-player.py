#!/usr/bin/env python3
"""sfx-player：常驻音效播放器（PipeWire）。

为什么：每条音效都新起 pw-play 要 ~110ms（新建 PipeWire 客户端 + 流协商），
实测与蓝牙无关（null sink 上同样 113-116ms）。这里把一条 pw-cat 原始输出流
一直开着（空闲时喂静音），音效名从 FIFO 一行一个送进来 → 起播只受
「当前静音块 + 管道缓冲」限制（默认 ~40ms，可调）。

协议：printf 'ui-click\n' > /run/user/1000/sfx.fifo
"""
import fcntl
import os
import queue
import subprocess
import sys
import time
import threading
import wave

FIFO = os.environ.get("SFX_FIFO", "/run/user/1000/sfx.fifo")
DIR = os.environ.get("SFX_DIR", os.path.expanduser("~/.local/share/sfx"))
RATE, CH = 48000, 2
BLOCK = 256                      # 静音块 = 5.3ms，块越小注入越及时
PIPE_BYTES = 4096
SIL = b"\x00" * (BLOCK * CH * 2)

# 预解码所有 wav 到内存（16bit 48k 立体声）
SOUNDS = {}
for entry in sorted(os.listdir(DIR)):
    if not entry.endswith(".wav"):
        continue
    try:
        with wave.open(os.path.join(DIR, entry)) as w:
            if (w.getframerate(), w.getnchannels(), w.getsampwidth()) == (RATE, CH, 2):
                SOUNDS[entry[:-4]] = w.readframes(w.getnframes())
    except Exception as exc:      # noqa: BLE001
        print(f"skip {entry}: {exc}", file=sys.stderr)

print(f"sfx-player: {len(SOUNDS)} sounds, fifo={FIFO}", file=sys.stderr)

pending = queue.Queue(maxsize=3)   # 满了就丢：宁可少响一次，也不要越积越滞后


def fifo_reader():
    while True:
        try:
            with open(FIFO, "r") as handle:
                for line in handle:
                    name = line.strip()
                    if not name:
                        continue
                    if name in SOUNDS:
                        try:
                            pending.put_nowait(SOUNDS[name])
                        except queue.Full:
                            pass
        except Exception as exc:  # noqa: BLE001
            print(f"fifo: {exc}", file=sys.stderr)


def main():
    if not os.path.exists(FIFO):
        os.mkfifo(FIFO, 0o600)
    threading.Thread(target=fifo_reader, daemon=True).start()

    player = subprocess.Popen(
        ["pw-cat", "--playback", "--raw", "--rate", str(RATE),
         "--channels", str(CH), "--format", "s16", "--latency", "20ms", "-"],
        stdin=subprocess.PIPE)
    try:
        fcntl.fcntl(player.stdin.fileno(), fcntl.F_SETPIPE_SZ, PIPE_BYTES)
    except OSError:
        pass

    while True:                        # 写进管道会被 pw-cat 按实时速率消费 → 天然限速
        try:
            chunk = pending.get_nowait()
        except queue.Empty:
            chunk = SIL
        player.stdin.write(chunk)
        player.stdin.flush()
        time.sleep(BLOCK / RATE * 0.9)


if __name__ == "__main__":
    main()
