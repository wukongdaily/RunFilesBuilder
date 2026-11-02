#!/bin/bash
# 解析 daeuniverse apk 源，提取 honk 全家桶的最新文件名。
#
# 为什么不用 packages.adb：apk v3 的索引是 "ADBd" 开头的压缩+签名二进制
# （实测 2153 B，hexdump 全是密文），runner 上没有 apk 工具解不开。
# 而 feed 开了目录浏览，直接读 HTML 目录列表更简单、更稳。
#
# 实测（2026-11-02）https://openwrt.daeuniverse.org/25.12/packages/x86_64/
#   honk-0.1.0_beta4-r3.apk                    16186820
#   luci-app-honk-26.303.60580~1046d3c.apk         2734
#   luci-lib-daeuniverse-26.303.64947~503cdb1.apk 10646
#   luci-i18n-daeuniverse-zh-cn-26.303...apk       2319
#   vmlinux-btf-builtin-1-r1.apk                    972
set -euo pipefail

FEED="${FEED:-https://openwrt.daeuniverse.org/25.12/packages}"
ENVF="${GITHUB_ENV:-/dev/stdout}"

list_apks() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -sfL --retry 3 --retry-delay 2 "$url"
    else
        wget -qO- --tries=3 "$url"
    fi
}

# 从 HTML 里挑出 href 以 $2 开头的 apk，取版本最大的一个。
# 前缀必须精确到连字符：honk- 不能把 luci-app-honk- 也吃进来
# （grep 模式是 href="honk- ，而 luci-app-honk 的 href 是 href="luci-app-honk- ，天然隔开）。
pick() {
    local html="$1" prefix="$2"
    printf '%s\n' "$html" \
        | grep -oE "href=\"${prefix}[^\"]*\.apk\"" \
        | sed -e 's/^href="//' -e 's/"$//' \
        | sort -V \
        | tail -n 1 || :
}

PREFIXES="honk- luci-app-honk- luci-lib-daeuniverse- luci-i18n-daeuniverse-zh-cn- vmlinux-btf-builtin-"

echo "=== 解析 apk 源: $FEED ==="

HONK_FILE=""
for arch in x86_64 aarch64_cortex-a53 aarch64_generic; do
    echo "--- $arch ---"
    html="$(list_apks "$FEED/$arch/")" || { echo "::error::抓不到 $FEED/$arch/"; exit 1; }

    case "$arch" in
        x86_64)             v="X86" ;;
        aarch64_cortex-a53) v="ARM_A53" ;;
        aarch64_generic)    v="ARM_GENERIC" ;;
    esac

    for p in $PREFIXES; do
        f="$(pick "$html" "$p")"
        if [ -z "$f" ]; then
            echo "::error::$arch 下找不到 ${p}* 的 apk"
            exit 1
        fi
        key="$(printf '%s' "$p" | sed 's/-$//' | tr 'a-z-' 'A-Z_')"
        echo "  $f"
        echo "${v}_${key}_URL=$FEED/$arch/$f" >> "$ENVF"
        [ "$p" = "honk-" ] && [ -z "$HONK_FILE" ] && HONK_FILE="$f"
    done
done

VERSION="$(printf '%s' "$HONK_FILE" | sed 's/^honk-//; s/\.apk$//')"
echo "VERSION=$VERSION" >> "$ENVF"

echo ""
echo "=== 解析完成 ==="
echo "honk 版本 : $VERSION"
echo "x86 honk  : $(printf '%s' "$HONK_FILE")"
