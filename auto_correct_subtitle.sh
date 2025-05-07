#!/bin/bash

# 字幕自動校正腳本 v3.1
# 
# 功能說明：
# 1. 自動從corrections.txt讀取Claude提供的錯字修正建議
# 2. 自動從known_words.txt讀取已知常見需要校正的文字
# 3. 對SRT字幕檔進行批量校正
# 4. 在執行腳本的資料夾下生成校正後的字幕檔
#
# 使用方法: ./auto_correct_subtitle.sh <subtitle.srt>
# 例如: ./auto_correct_subtitle.sh my_subtitle.srt
#
# 檔案說明:
# - corrections.txt: Claude提供的錯字修正建議，格式為 "[時間戳記] 行號:原文:修正後 - 說明"
# - known_words.txt: 已知常見需要校正的文字，格式為 "原文 > 修正後"
# - <subtitle.srt>: 需要校正的字幕檔
# - <subtitle.srt>.corrected: 校正後的字幕檔
# - <subtitle.srt>.bak: 原始字幕檔的備份

# 標題和版本資訊
echo "==================================================="
echo "           SRT 字幕自動校正腳本 v3.1              "
echo "==================================================="

# 檢查參數
if [ $# -ne 1 ]; then
    echo "用法: $0 <subtitle.srt>"
    echo "例如: $0 my_subtitle.srt"
    exit 1
fi

# 獲取腳本所在目錄（而非當前工作目錄）
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# 設定檔案路徑
SRT_FILE="$1"
if [[ ! "$SRT_FILE" = /* ]]; then
    SRT_FILE="$(pwd)/$SRT_FILE"
fi

CORRECTIONS_FILE="$SCRIPT_DIR/corrections.txt"
KNOWN_WORDS_FILE="$SCRIPT_DIR/known_words.txt"
BACKUP_FILE="$SCRIPT_DIR/$(basename "$SRT_FILE").bak"
OUTPUT_FILE="$SCRIPT_DIR/$(basename "$SRT_FILE").corrected"

echo "字幕檔案: $SRT_FILE"
echo "Claude修正建議檔案: $CORRECTIONS_FILE"
echo "已知錯字檔案: $KNOWN_WORDS_FILE"
echo "輸出檔案: $OUTPUT_FILE"

# 檢查SRT檔案是否存在
if [ ! -f "$SRT_FILE" ]; then
    echo "錯誤: 字幕檔案不存在! 請確認檔案路徑正確。"
    exit 1
fi

# 檢查corrections.txt檔案是否存在
if [ ! -f "$CORRECTIONS_FILE" ]; then
    echo "警告: corrections.txt檔案不存在! 將跳過Claude修正建議處理。"
    HAS_CORRECTIONS=false
else
    HAS_CORRECTIONS=true
fi

# 檢查known_words.txt檔案是否存在
if [ ! -f "$KNOWN_WORDS_FILE" ]; then
    echo "警告: known_words.txt檔案不存在! 將跳過常見錯字處理。"
    HAS_KNOWN_WORDS=false
else
    HAS_KNOWN_WORDS=true
fi

# 如果兩個輸入檔案都不存在，則退出
if [ "$HAS_CORRECTIONS" = false ] && [ "$HAS_KNOWN_WORDS" = false ]; then
    echo "錯誤: corrections.txt和known_words.txt都不存在! 無法進行任何校正。"
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

# 處理統計
CORRECTIONS_COUNT=0
KNOWN_WORDS_COUNT=0
ERRORS_COUNT=0

# 全文搜索而非映射方式
# 處理 Claude 建議的修正
if [ "$HAS_CORRECTIONS" = true ]; then
    echo -e "\n開始套用Claude建議的修正..."
    
    while IFS= read -r line; do
        # 跳過空行、註釋行和只有"-"的行
        if [[ -z "$line" || "$line" == \#* || "$line" == "-" ]]; then
            continue
        fi
        
        # 檢測是否包含時間戳記格式 [xx:xx:xx]
        if echo "$line" | grep -q -E '^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]'; then
            # 使用手動拆分處理時間戳記後的部分
            # 首先獲取時間戳記
            timestamp=$(echo "$line" | grep -o -E '^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]' | tr -d '[]')
            
            # 移除時間戳記部分，獲取剩餘部分
            content_part=$(echo "$line" | sed -E 's/^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\] //')
            
            # 以冒號分隔，提取字幕序號、原文和修正後內容
            IFS=':' read -r subtitle_number original corrected_tmp <<< "$content_part"
            # 獲取可能的剩餘部分（如果有多個冒號）
            corrected=$(echo "$content_part" | sed -E "s/^$subtitle_number:$original://")
            
            # 處理可能的空格
            subtitle_number=$(echo "$subtitle_number" | sed 's/^ *//;s/ *$//')
            original=$(echo "$original" | sed 's/^ *//;s/ *$//')
            corrected=$(echo "$corrected" | sed 's/^ *//;s/ *$//')
            
            # 檢查是否成功解析
            if [[ -z "$subtitle_number" || -z "$original" || -z "$corrected" ]]; then
                echo "警告: 無法解析建議內容: $line"
                ((ERRORS_COUNT++))
                continue
            fi
            
            # 全文搜索原文
            match_lines=$(grep -n "$original" "$OUTPUT_FILE" 2>/dev/null || echo "")
            
            if [[ -n "$match_lines" ]]; then
                # 取第一個匹配行
                first_match=$(echo "$match_lines" | head -n 1)
                line_number=$(echo "$first_match" | cut -d':' -f1)
                
                # 替換內容 (使用sed的特殊方式處理可能包含特殊字符的字串)
                original_escaped=$(echo "$original" | sed 's/[\/&]/\\&/g')
                corrected_escaped=$(echo "$corrected" | sed 's/[\/&]/\\&/g')
                
                if [[ "$(uname)" == "Darwin" ]]; then
                    # macOS版本
                    sed -i '' "${line_number}s/$original_escaped/$corrected_escaped/g" "$OUTPUT_FILE"
                else
                    # Linux版本
                    sed -i "${line_number}s/$original_escaped/$corrected_escaped/g" "$OUTPUT_FILE"
                fi
                
                # 輸出修正訊息
                echo "[$timestamp] 已修正 (第 $line_number 行): '$original' -> '$corrected'"
                
                ((CORRECTIONS_COUNT++))
            else
                echo "警告: 找不到原文: '$original'"
                ((ERRORS_COUNT++))
                continue
            fi
        else
            echo "警告: 無法識別時間戳記格式: $line"
            ((ERRORS_COUNT++))
            continue
        fi
    done < "$CORRECTIONS_FILE"
    
    echo "Claude建議修正完成! 共套用了 $CORRECTIONS_COUNT 個修正。"
fi

# 處理已知的常見錯字
if [ "$HAS_KNOWN_WORDS" = true ]; then
    echo -e "\n開始套用已知常見錯字修正..."
    
    while IFS= read -r line; do
        # 跳過空行、註釋行和格式不正確的行
        if [[ -z "$line" || "$line" == \#* || ! "$line" == *">"* ]]; then
            continue
        fi
        
        # 檢查是否需要區分大小寫
        if [[ "$line" == *"[case]"* ]]; then
            CASE_SENSITIVE=true
            # 移除[case]標記
            line=$(echo "$line" | sed 's/\s*\[case\]\s*$//')
        else
            CASE_SENSITIVE=false
        fi
        
        # 分離原文和修正後的文字
        original=$(echo "$line" | sed 's/\s*>.*$//' | sed 's/^ *//;s/ *$//')
        corrected=$(echo "$line" | sed 's/^.*>\s*//' | sed 's/^ *//;s/ *$//')
        
        # 檢查是否成功解析
        if [[ -z "$original" || -z "$corrected" ]]; then
            echo "警告: 無法解析常見錯字: $line"
            ((ERRORS_COUNT++))
            continue
        fi
        
        # 計算替換前的行數
        before_lines=$(wc -l < "$OUTPUT_FILE")
        
        # 替換所有出現的錯字
        original_escaped=$(echo "$original" | sed 's/[\/&]/\\&/g')
        corrected_escaped=$(echo "$corrected" | sed 's/[\/&]/\\&/g')
        
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS版本
            if [ "$CASE_SENSITIVE" = true ]; then
                # 區分大小寫替換
                sed -i '' "s/$original_escaped/$corrected_escaped/g" "$OUTPUT_FILE"
            else
                # 不區分大小寫替換
                sed -i '' "s/$original_escaped/$corrected_escaped/gi" "$OUTPUT_FILE"
            fi
        else
            # Linux版本
            if [ "$CASE_SENSITIVE" = true ]; then
                # 區分大小寫替換
                sed -i "s/$original_escaped/$corrected_escaped/g" "$OUTPUT_FILE"
            else
                # 不區分大小寫替換
                sed -i "s/$original_escaped/$corrected_escaped/gi" "$OUTPUT_FILE"
            fi
        fi
        
        case_info=""
        if [ "$CASE_SENSITIVE" = true ]; then
            case_info="(區分大小寫)"
        else
            case_info="(不區分大小寫)"
        fi
        
        # 計算替換後的行數（確保文件未損壞）
        after_lines=$(wc -l < "$OUTPUT_FILE")
        
        if [ "$before_lines" -eq "$after_lines" ]; then
            # 輸出修正訊息
            echo "已全局替換常見錯字: '$original' -> '$corrected' $case_info"
            ((KNOWN_WORDS_COUNT++))
        else
            echo "警告: 替換 '$original' 後文件行數改變，可能發生錯誤！"
            # 還原到備份
            cp "$BACKUP_FILE" "$OUTPUT_FILE"
            echo "已還原到備份檔案！"
            exit 1
        fi
        
    done < "$KNOWN_WORDS_FILE"
    
    echo "常見錯字修正完成! 共套用了 $KNOWN_WORDS_COUNT 個全局替換。"
fi

echo -e "\n==================================================="
echo "校正完成!"
echo "Claude建議修正: $CORRECTIONS_COUNT 個"
echo "常見錯字替換: $KNOWN_WORDS_COUNT 個"
if [ $ERRORS_COUNT -gt 0 ]; then
    echo "遇到 $ERRORS_COUNT 個無法處理的建議。"
fi
echo "原始檔案備份為: $BACKUP_FILE"
echo "修正後的檔案為: $OUTPUT_FILE"
echo "==================================================="