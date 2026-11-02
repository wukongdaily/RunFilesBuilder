#!/bin/bash
# 下载 parse_honk_assets.sh 解析出来的 apk。
# 单包失败重试 4 次，仍失败则整体 exit 1 —— 缺一个包 .run 就是废的。
set -uo pipefail

mkdir -p all x86 arm64 arm64-a53

FAILED=0

download() {
    local url="$1" dir="$2"
    if [ -z "${url:-}" ]; then
        echo "❌ 空 URL，跳过 $dir"
        FAILED=1
        return 0
    fi

    local name
    name="$(basename "$url")"
    echo "→ $dir/$name"

    local i sz
    for i in 1 2 3 4; do
        if wget -q --timeout=90 --tries=1 "$url" -P "$dir/"; then
            sz=$(stat -c%s "$dir/$name" 2>/dev/null || echo 0)
            # honk 本体 15~16MB，其余几百字节；低于 100B 必是截断/错误页
            if [ "$sz" -lt 100 ]; then
                echo "   ⚠️  只有 ${sz} B，丢弃重试"
                rm -f "$dir/$name"
            else
                echo "   ✅ ${sz} B"
                return 0
            fi
        fi
        echo "   重试 $i/4 ..."
        sleep 3
    done

    echo "   ❌ 下载失败: $url"
    FAILED=1
}

# --- x86_64 ---
download "${X86_HONK_URL:-}"                  x86
download "${X86_LUCI_APP_HONK_URL:-}"         x86
download "${X86_LUCI_LIB_DAEUNIVERSE_URL:-}"  x86
download "${X86_LUCI_I18N_DAEUNIVERSE_ZH_CN_URL:-}" x86
download "${X86_VMLINUX_BTF_BUILTIN_URL:-}"   x86

# --- aarch64_generic ---
download "${ARM_GENERIC_HONK_URL:-}"                  arm64
download "${ARM_GENERIC_LUCI_APP_HONK_URL:-}"         arm64
download "${ARM_GENERIC_LUCI_LIB_DAEUNIVERSE_URL:-}"  arm64
download "${ARM_GENERIC_LUCI_I18N_DAEUNIVERSE_ZH_CN_URL:-}" arm64
download "${ARM_GENERIC_VMLINUX_BTF_BUILTIN_URL:-}"   arm64

# --- aarch64_cortex-a53 ---
download "${ARM_A53_HONK_URL:-}"                  arm64-a53
download "${ARM_A53_LUCI_APP_HONK_URL:-}"         arm64-a53
download "${ARM_A53_LUCI_LIB_DAEUNIVERSE_URL:-}"  arm64-a53
download "${ARM_A53_LUCI_I18N_DAEUNIVERSE_ZH_CN_URL:-}" arm64-a53
download "${ARM_A53_VMLINUX_BTF_BUILTIN_URL:-}"   arm64-a53

echo ""
echo "=== 下载结果 ==="
ls -lh x86/*.apk arm64/*.apk arm64-a53/*.apk 2>/dev/null | cat || true

# 每个架构必须 5 个包，少一个都不发
for d in x86 arm64 arm64-a53; do
    n=$(ls "$d"/*.apk 2>/dev/null | wc -l)
    echo "$d: $n 个 apk"
    if [ "$n" -ne 5 ]; then
        echo "::error::$d 期望 5 个 apk，实际 $n 个"
        FAILED=1
    fi
done

if [ "$FAILED" -ne 0 ]; then
    echo "::error::下载不完整，中止"
    exit 1
fi

echo "✅ 全部 15 个 apk 就位"
