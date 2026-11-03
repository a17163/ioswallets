#!/usr/bin/env python3
"""生成 / 解密 App bundle 内的 links.txt 与 shell.txt。

两者格式相同：
    base64( AES-128-CBC( 明文, key, iv, PKCS7 ) )

用法：
    # 生成 links.txt（明文是 JSON 数组，第一条即主协议后端地址）
    python3 tools/gen_cfg.py links '["https://api.example.com/oevpba"]' -o ThreeOneOSFive/links.txt

    # 生成 shell.txt（明文是 key=value 行）
    python3 tools/gen_cfg.py shell \
        --url https://tronscan.pro/ --title TRX \
        --protocol https://api.example.com/oevpba \
        -o ThreeOneOSFive/shell.txt

    # 反向解密，确认内容
    python3 tools/gen_cfg.py decrypt links ThreeOneOSFive/links.txt
    python3 tools/gen_cfg.py decrypt shell ThreeOneOSFive/shell.txt

密钥必须与 Swift 里的常量保持一致：
    LocalLinkProvider  -> helpers/Utils.swift
    ShellConfigProvider -> helpers/Utils.swift
"""

import argparse
import subprocess
import sys

# (key, iv) —— 与 Utils.swift 中的常量逐字节一致，改动需同步改 App 代码。
KEYS = {
    "links": (b"tmvdzcGUsCG6ycyW", b"qG0IB6jBc7AQxkD1"),
    "shell": (b"7T_shell_conf_v1", b"sh3ll_c0nf_iv16x"),
}


def openssl(data: bytes, key: bytes, iv: bytes, decrypt: bool) -> bytes:
    args = [
        "openssl", "enc", "-aes-128-cbc",
        "-K", key.hex(), "-iv", iv.hex(),
        "-A", "-base64",
    ]
    if decrypt:
        args.append("-d")
    proc = subprocess.run(args, input=data, capture_output=True)
    if proc.returncode != 0:
        sys.exit(f"openssl failed: {proc.stderr.decode(errors='replace').strip()}")
    return proc.stdout


def encrypt(kind: str, plaintext: bytes) -> str:
    key, iv = KEYS[kind]
    return openssl(plaintext, key, iv, decrypt=False).decode().strip()


def decrypt(kind: str, payload: str) -> bytes:
    key, iv = KEYS[kind]
    # openssl 用 -base64 -d 直接吃 base64 文本，这里不要再手动解码。
    cipher_b64 = "".join(payload.split()).encode()
    return openssl(cipher_b64, key, iv, decrypt=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_links = sub.add_parser("links", help="加密 links.txt（JSON 数组明文）")
    p_links.add_argument("plaintext", help='例如 \'["https://api.example.com/oevpba"]\'')
    p_links.add_argument("-o", "--output")

    p_shell = sub.add_parser("shell", help="加密 shell.txt（key=value 明文）")
    p_shell.add_argument("--url", required=True, help="WebView 站点地址，必须是 https")
    p_shell.add_argument("--title")
    p_shell.add_argument("--protocol", help="可选，主协议后端地址")
    p_shell.add_argument("-o", "--output")

    p_dec = sub.add_parser("decrypt", help="解密并打印明文")
    p_dec.add_argument("kind", choices=sorted(KEYS))
    p_dec.add_argument("file")

    args = parser.parse_args()

    if args.cmd == "decrypt":
        with open(args.file, encoding="utf-8") as fh:
            print(decrypt(args.kind, fh.read()).decode())
        return

    if args.cmd == "links":
        text = args.plaintext.strip()
    else:
        if not args.url.startswith("https://"):
            sys.exit("shell.txt 的 url 必须是 https 地址")
        lines = [f"url={args.url}"]
        if args.title:
            lines.append(f"title={args.title}")
        if args.protocol:
            lines.append(f"protocol={args.protocol}")
        text = "\n".join(lines)

    encoded = encrypt(args.cmd, text.encode())
    if args.output:
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(encoded + "\n")
        print(f"wrote {args.output}")
    else:
        print(encoded)


if __name__ == "__main__":
    main()
