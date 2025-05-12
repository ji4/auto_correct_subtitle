#!/bin/bash

# 字幕自動校正腳本 v3.5
# 
# 功能說明：
# 1. 自動從corrections.txt讀取Claude提供的錯字修正建議
# 2. 自動從known_words.txt讀取已知常見需要校正的文字
# 3. 直接對SRT字幕檔進行批量校正（直接修改原檔）
# 4. 在執行前會創建備份檔案以防止資料丟失
# 5. 備份檔案保存在腳本所在目錄
# 6. 支持透過字幕編號進行精確替換，如找不到則自動退回到全文搜索
#
# 使用方法: ./auto_correct_subtitle.sh <subtitle.srt> [選項]
# 例如: ./auto_correct_subtitle.sh my_subtitle.srt
# 選項:
#   --no-subtitle-id  不使用字幕編號進行替換，直接用全文搜索方式
#
# 檔案說明:
# - corrections.txt: Claude提供的錯字修正建議，格式為 "[時間戳記] 行號:原文:修正後 - 說明"
# - known_words.txt: 已知常見需要校正的文字，格式為 "原文 > 修正後"
# - <subtitle.srt>: 需要校正的字幕檔
# - <script_dir>/<subtitle_basename>.srt.bak: 原始字幕檔的備份（保存在腳本目錄）

# 標題和版本資訊
echo "==================================================="
echo "           SRT 字幕自動校正腳本 v3.5              "
echo "==================================================="

# 默認設置
USE_SUBTITLE_ID=true

# 處理參數
SRT_FILE=""
for arg in "$@"; do
    if [[ "$arg" == "--no-subtitle-id" ]]; then
        USE_SUBTITLE_ID=false
    elif [[ "$arg" != -* ]]; then
        SRT_FILE="$arg"
    fi
done

# 檢查是否提供了字幕文件
if [ -z "$SRT_FILE" ]; then
    echo "用法: $0 <subtitle.srt> [選項]"
    echo "例如: $0 my_subtitle.srt"
    echo "選項:"
    echo "  --no-subtitle-id  不使用字幕編號進行替換，直接用全文搜索方式"
    exit 1
fi

# 獲取腳本所在目錄（而非當前工作目錄）
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# 設定檔案路徑
if [[ ! "$SRT_FILE" = /* ]]; then
    SRT_FILE="$(pwd)/$SRT_FILE"
fi

# 獲取字幕檔案的基本名稱（不含路徑）
SRT_BASENAME=$(basename "$SRT_FILE")

CORRECTIONS_FILE="$SCRIPT_DIR/corrections.txt"
KNOWN_WORDS_FILE="$SCRIPT_DIR/known_words.txt"
# 修改備份檔案的路徑，使其保存在腳本目錄下
BACKUP_FILE="$SCRIPT_DIR/${SRT_BASENAME}.bak"

echo "字幕檔案: $SRT_FILE"
echo "Claude修正建議檔案: $CORRECTIONS_FILE"
echo "已知錯字檔案: $KNOWN_WORDS_FILE"
echo "備份檔案: $BACKUP_FILE"
if [ "$USE_SUBTITLE_ID" = true ]; then
    echo "替換模式: 優先使用字幕編號進行替換，找不到時自動退回到全文搜索"
else
    echo "替換模式: 使用全文搜索方式（不考慮字幕編號）"
fi

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
    echo "發現腳本目錄下存在舊的備份檔案，將被刪除..."
    rm "$BACKUP_FILE"
fi

# 創建備份
cp "$SRT_FILE" "$BACKUP_FILE"
echo "已在腳本目錄下創建備份檔案: $BACKUP_FILE"

# 處理統計
CORRECTIONS_COUNT=0
KNOWN_WORDS_COUNT=0
ERRORS_COUNT=0

# 函數：使用全文搜索方式替換文本
do_global_search_replace() {
    local timestamp="$1"
    local subtitle_number="$2"
    local original="$3"
    local corrected="$4"
    
    # 使用全文搜索方式
    match_lines=$(grep -n "$original" "$SRT_FILE" 2>/dev/null || echo "")
    
    if [[ -n "$match_lines" ]]; then
        # 取第一個匹配行
        first_match=$(echo "$match_lines" | head -n 1)
        line_number=$(echo "$first_match" | cut -d':' -f1)
        
        # 替換內容 (使用sed的特殊方式處理可能包含特殊字符的字串)
        original_escaped=$(echo "$original" | sed 's/[\/&]/\\&/g')
        corrected_escaped=$(echo "$corrected" | sed 's/[\/&]/\\&/g')
        
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS版本
            sed -i '' "${line_number}s/$original_escaped/$corrected_escaped/g" "$SRT_FILE"
        else
            # Linux版本
            sed -i "${line_number}s/$original_escaped/$corrected_escaped/g" "$SRT_FILE"
        fi
        
        # 輸出修正訊息
        echo "[$timestamp] 已修正 (全文搜索, 第 $line_number 行): '$original' -> '$corrected'"
        return 0 # 成功
    else
        echo "警告: 找不到原文: '$original'"
        return 1 # 失敗
    fi
}

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
            
            # 根據選擇的模式進行替換
            if [ "$USE_SUBTITLE_ID" = true ] && [[ "$subtitle_number" =~ ^[0-9]+$ ]]; then
                # 使用字幕編號進行替換
                # 暫存檔案路徑
                TEMP_FILE=$(mktemp)
                
                # 處理字幕文件的變數
                current_subtitle=""
                in_subtitle=false
                found=false
                line_number=0
                
                # 讀取SRT文件並進行特定字幕編號的替換
                while IFS= read -r srt_line; do
                    ((line_number++))
                    
                    # 檢查是否為純數字行（字幕編號）
                    if [[ "$srt_line" =~ ^[0-9]+$ ]]; then
                        if [ "$in_subtitle" = true ]; then
                            # 寫入之前處理過的字幕
                            echo "$current_subtitle" >> "$TEMP_FILE"
                        fi
                        
                        # 新的字幕開始
                        current_subtitle="$srt_line"
                        in_subtitle=true
                        
                        # 檢查是否為目標字幕編號
                        if [ "$srt_line" = "$subtitle_number" ]; then
                            target_subtitle=true
                        else
                            target_subtitle=false
                        fi
                    elif [ "$in_subtitle" = true ]; then
                        # 在字幕內部
                        if [ "$target_subtitle" = true ] && echo "$srt_line" | grep -q "$original"; then
                            # 進行替換
                            original_escaped=$(echo "$original" | sed 's/[\/&]/\\&/g')
                            corrected_escaped=$(echo "$corrected" | sed 's/[\/&]/\\&/g')
                            new_line=$(echo "$srt_line" | sed "s/$original_escaped/$corrected_escaped/g")
                            current_subtitle="$current_subtitle"$'\n'"$new_line"
                            found=true
                            replace_line_number=$line_number
                        else
                            # 正常添加行
                            current_subtitle="$current_subtitle"$'\n'"$srt_line"
                        fi
                    else
                        # 不在字幕內部，直接寫入
                        echo "$srt_line" >> "$TEMP_FILE"
                    fi
                done < "$SRT_FILE"
                
                # 處理最後一個字幕
                if [ "$in_subtitle" = true ]; then
                    echo "$current_subtitle" >> "$TEMP_FILE"
                fi
                
                # 如果在指定字幕中找到並替換了文字
                if [ "$found" = true ]; then
                    # 用處理後的文件替換原文件
                    mv "$TEMP_FILE" "$SRT_FILE"
                    
                    # 輸出修正信息
                    echo "[$timestamp] 已修正 (字幕編號 $subtitle_number, 行 $replace_line_number): '$original' -> '$corrected'"
                    ((CORRECTIONS_COUNT++))
                else
                    # 在指定字幕中找不到要替換的文字，嘗試使用全文搜索
                    echo "在字幕編號 $subtitle_number 中找不到原文，嘗試使用全文搜索..."
                    # 移除臨時文件
                    rm "$TEMP_FILE"
                    
                    # 使用全文搜索方式替換
                    if do_global_search_replace "$timestamp" "$subtitle_number" "$original" "$corrected"; then
                        ((CORRECTIONS_COUNT++))
                    else
                        ((ERRORS_COUNT++))
                    fi
                fi
            else
                # 直接使用全文搜索方式（原始方法）
                if do_global_search_replace "$timestamp" "$subtitle_number" "$original" "$corrected"; then
                    ((CORRECTIONS_COUNT++))
                else
                    ((ERRORS_COUNT++))
                fi
            fi
        else
            echo "警告: 無法識別時間戳記格式: $line"
            ((ERRORS_COUNT++))
            continue
        fi
    done < "$CORRECTIONS_FILE"
    
    echo "Claude建議修正完成! 共套用了 $CORRECTIONS_COUNT 個修正。"
fi

# 處理已知的常見錯字（與之前相同）
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
        before_lines=$(wc -l < "$SRT_FILE")
        
        # 替換所有出現的錯字
        original_escaped=$(echo "$original" | sed 's/[\/&]/\\&/g')
        corrected_escaped=$(echo "$corrected" | sed 's/[\/&]/\\&/g')
        
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS版本
            if [ "$CASE_SENSITIVE" = true ]; then
                # 區分大小寫替換
                sed -i '' "s/$original_escaped/$corrected_escaped/g" "$SRT_FILE"
            else
                # 不區分大小寫替換
                sed -i '' "s/$original_escaped/$corrected_escaped/gi" "$SRT_FILE"
            fi
        else
            # Linux版本
            if [ "$CASE_SENSITIVE" = true ]; then
                # 區分大小寫替換
                sed -i "s/$original_escaped/$corrected_escaped/g" "$SRT_FILE"
            else
                # 不區分大小寫替換
                sed -i "s/$original_escaped/$corrected_escaped/gi" "$SRT_FILE"
            fi
        fi
        
        case_info=""
        if [ "$CASE_SENSITIVE" = true ]; then
            case_info="(區分大小寫)"
        else
            case_info="(不區分大小寫)"
        fi
        
        # 計算替換後的行數（確保文件未損壞）
        after_lines=$(wc -l < "$SRT_FILE")
        
        if [ "$before_lines" -eq "$after_lines" ]; then
            # 輸出修正訊息
            echo "已全局替換常見錯字: '$original' -> '$corrected' $case_info"
            ((KNOWN_WORDS_COUNT++))
        else
            echo "警告: 替換 '$original' 後文件行數改變，可能發生錯誤！"
            # 還原到備份
            cp "$BACKUP_FILE" "$SRT_FILE"
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
echo "原始檔案備份為: $BACKUP_FILE (位於腳本目錄)"
echo "原始檔案已被直接修改"
echo "==================================================="