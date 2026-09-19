#!/bin/sh
# 生成目录树和文本内容，输出到当前目录的“文件夹列出.txt”
# 用法: ./tree_with_content.sh [目标目录]   (默认当前目录)

set -e

# 输出文件放在当前工作目录（脚本执行目录）
ORIGINAL_DIR="$(pwd)"
OUTPUT_FILE="${ORIGINAL_DIR}/文件夹列出.txt"
> "$OUTPUT_FILE"   # 清空或创建

# 切换到目标目录
TARGET_DIR="${1:-.}"
cd "$TARGET_DIR" || { echo "错误: 无法进入目录 $TARGET_DIR"; exit 1; }

# 递归函数：打印树形结构并写入文件
print_tree() {
    dir="$1"
    prefix="$2"

    # 计算相对路径（用于提示信息）
    rel_path="${dir#./}"
    [ "$rel_path" = "." ] && rel_path=""

    # 处理子目录
    for item in "$dir"/*; do
        [ -e "$item" ] || continue
        name=$(basename "$item")

        # 如果位于起始目录且文件名与输出文件同名，跳过（避免自我引用）
        if [ -z "$rel_path" ] && [ "$name" = "文件夹列出.txt" ]; then
            continue
        fi

        if [ -d "$item" ]; then
            # 目录
            line="${prefix}📁$name/"
            echo "$line" >> "$OUTPUT_FILE"
            echo "已写入 $rel_path$name"   # 终端提示
            print_tree "$item" "${prefix}   "
        fi
    done

    # 处理文件
    for item in "$dir"/*; do
        [ -f "$item" ] || continue
        name=$(basename "$item")

        if [ -z "$rel_path" ] && [ "$name" = "文件夹列出.txt" ]; then
            continue
        fi

        # 文件行
        line="${prefix}📄$name"
        echo -n "$line" >> "$OUTPUT_FILE"
        echo "已写入 $rel_path$name"   # 终端提示

        # 判断是否为常见文本文件
        ext="${name##*.}"
        case "$ext" in
            gd|tscn|md|json|cfg|txt|svg|gdshader|css|js|html|sh|py|xml|yaml|yml|conf|ini)
                echo ":" >> "$OUTPUT_FILE"
                # 逐行写入内容，每行缩进
                while IFS= read -r content_line; do
                    echo "${prefix}   $content_line" >> "$OUTPUT_FILE"
                done < "$item"
                ;;
            *)
                echo " (binary)" >> "$OUTPUT_FILE"
                ;;
        esac
    done
}

# 写入根目录
ROOT_NAME=$(basename "$(pwd)")
echo "📁$ROOT_NAME/" >> "$OUTPUT_FILE"
echo "已写入 $ROOT_NAME/"

# 开始递归
print_tree "." ""

echo "完成！结果已保存到 $OUTPUT_FILE"