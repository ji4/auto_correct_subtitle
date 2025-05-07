#!/bin/bash

# 字幕自動校正腳本
# 使用方法: ./auto_correct_subtitle.sh <claude_suggestions.txt> <subtitle.srt>

# 標題和版本資訊
echo "==================================================="
echo "           SRT 字幕自動校正腳本 v1.0              "
echo "==================================================="

# 檢查參數
if [ $# -ne 2 ]; then
    echo "用法: $0 <claude_suggestions.txt> <subtitle.srt>"
    echo "例如: $0 corrections.txt my_subtitle.srt"
    exit 1
fi

# 獲取腳本所在目錄（而非當前工作目錄）
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# 處理輸入檔案路徑
SUGGESTIONS_FILE="$1"
SRT_FILE="$2"

# 如果提供的是相對路徑，則基於當前工作目錄
if [[ ! "$SUGGESTIONS_FILE" = /* ]]; then
    SUGGESTIONS_FILE="$(pwd)/$SUGGESTIONS_FILE"
fi

if [[ ! "$SRT_FILE" = /* ]]; then
    SRT_FILE="$(pwd)/$SRT_FILE"
fi

# 輸出檔案將與腳本放在同一個資料夾
BACKUP_FILE="$SCRIPT_DIR/$(basename "$SRT_FILE").bak"
OUTPUT_FILE="$SCRIPT_DIR/$(basename "$SRT_FILE").corrected"

echo "建議檔案: $SUGGESTIONS_FILE"
echo "字幕檔案: $SRT_FILE"
echo "輸出檔案: $OUTPUT_FILE"

# 檢查建議檔案是否存在
if [ ! -f "$SUGGESTIONS_FILE" ]; then
    echo "錯誤: 建議檔案不存在! 請確認檔案路徑正確。"
    exit 1
fi

# 檢查SRT檔案是否存在
if [ ! -f "$SRT_FILE" ]; then
    echo "錯誤: 字幕檔案不存在! 請確認檔案路徑正確。"
    exit 1
fi

# 如果備份檔案已存在，先刪除它
if [ -f "$BACKUP_FILE" ]; then
    echo "發現舊的備份檔案，將被刪除..."
    rm "$BACKUP_FILE"
fi

# 創建備份
cp "$SRT_FILE" "$BACKUP_FILE"
echo "已創建備份檔案: $BACKUP_FILE"

# 如果輸出檔案已存在，先清空它
if [ -f "$OUTPUT_FILE" ]; then
    echo "輸出檔案已存在，將被覆寫..."
    > "$OUTPUT_FILE"
else
    touch "$OUTPUT_FILE"
fi

# 先複製原始檔案到輸出檔案
cp "$SRT_FILE" "$OUTPUT_FILE"

# 讀取並處理每一行建議
echo -e "\n開始套用修正..."
CORRECTIONS_COUNT=0
ERRORS_COUNT=0

while IFS= read -r line; do
    # 跳過空行和註釋行
    if [[ -z "$line" || "$line" == \#* ]]; then
        continue
    fi
    
    # 提取時間戳記、行號、原文和修正內容
    if [[ "$line" =~ ^\[(.*?)\] ]]; then
        # 提取時間戳記
        timestamp="${BASH_REMATCH[1]}"
        # 移除時間戳記部分，處理剩餘內容
        content_part="${line#*] }"
    else
        # 如果沒有時間戳記
        timestamp="未知時間"
        content_part="$line"
    fi
    
    # 提取行號、原文和修正內容，忽略註記部分
    if [[ "$content_part" == *" - "* ]]; then
        # 有註記的情況
        main_part=$(echo "$content_part" | sed 's/\s*-.*$//')
        note_part=$(echo "$content_part" | sed 's/^.*-\s*//')
        IFS=':' read -r line_number original corrected <<< "$main_part"
    else
        # 沒有註記的情況
        IFS=':' read -r line_number original corrected <<< "$content_part"
        note_part=""
    fi
    
    # 處理可能的空格
    line_number=$(echo "$line_number" | xargs)
    original=$(echo "$original" | xargs)
    corrected=$(echo "$corrected" | xargs)
    
    # 檢查是否成功解析
    if [[ -z "$line_number" || -z "$original" || -z "$corrected" ]]; then
        echo "警告: 無法解析建議: $line"
        ((ERRORS_COUNT++))
        continue
    fi
    
    # 檢查行號是否為數字
    if ! [[ "$line_number" =~ ^[0-9]+$ ]]; then
        echo "警告: 行號不是數字: $line_number"
        ((ERRORS_COUNT++))
        continue
    fi
    
    # 提取目標行的內容
    target_line=$(sed -n "${line_number}p" "$OUTPUT_FILE")
    
    # 檢查原文是否在目標行中
    if [[ "$target_line" != *"$original"* ]]; then
        echo "警告: 在第 $line_number 行找不到原文: '$original'"
        echo "實際內容: '$target_line'"
        ((ERRORS_COUNT++))
        continue
    fi
    
    # 替換內容 (使用sed的特殊方式處理可能包含特殊字符的字串)
    original_escaped=$(echo "$original" | sed 's/[\/&]/\\&/g')
    corrected_escaped=$(echo "$corrected" | sed 's/[\/&]/\\&/g')
    sed -i "${line_number}s/$original_escaped/$corrected_escaped/g" "$OUTPUT_FILE"
    
    # 輸出修正訊息，包含時間戳記
    if [[ -n "$note_part" ]]; then
        echo "[$timestamp] 已修正第 $line_number 行: '$original' -> '$corrected' - $note_part"
    else
        echo "[$timestamp] 已修正第 $line_number 行: '$original' -> '$corrected'"
    fi
    
    ((CORRECTIONS_COUNT++))
done < "$SUGGESTIONS_FILE"

echo -e "\n==================================================="
echo "完成! 共套用了 $CORRECTIONS_COUNT 個修正。"
if [ $ERRORS_COUNT -gt 0 ]; then
    echo "遇到 $ERRORS_COUNT 個無法處理的建議。"
fi
echo "原始檔案備份為: $BACKUP_FILE"
echo "修正後的檔案為: $OUTPUT_FILE"
echo "==================================================="