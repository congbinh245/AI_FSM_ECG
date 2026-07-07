import pandas as pd
import numpy as np
import glob
import os
import json
from scipy.signal import resample

# ==========================================
# CẤU HÌNH (CONFIGURATION)
# ==========================================
FS_ORIGINAL     = 360       # Tần số mẫu gốc MIT-BIH
FS_HARDWARE     = 250       # Tần số mẫu FPGA (Target)
WINDOW_SAMPLES  = 500       # Cửa sổ tại 360Hz (~1.39s)
HALF_WINDOW     = WINDOW_SAMPLES // 2
folder_path     = "E:/code/archive"  # ĐƯỜNG DẪN DỮ LIỆU CỦA BẠN

# Sau khi resample: 500 mẫu (360Hz) -> ~347 mẫu (250Hz)
WINDOW_RESAMPLED = int(WINDOW_SAMPLES * FS_HARDWARE / FS_ORIGINAL)

# Các ký hiệu nhịp tim từ MIT-BIH
valid_symbols = ['N','L','R','A','a','J','S','V','F','[','!','e','j','E','/','f','x','Q','|',']']
arrhythmia_minor = ['A', 'a', 'J', 'S'] # Rối loạn nhẹ
arrhythmia_major = ['V', 'F', 'L', 'R', 'E'] # Rối loạn nặng

# ==========================================
# FEATURE EXTRACTION — TỐI ƯU CHO MODEL 12-8-4
# Thay đổi: Thêm ngữ cảnh chuỗi thời gian (RR History)
# ==========================================
def extract_12_features(signal, rr_curr, rr_prev):
    """
    Trích xuất 12 đặc trưng phù hợp FPGA.
    signal: Mảng tín hiệu đã resample về 250Hz
    rr_curr: Khoảng cách nhịp hiện tại (giây)
    rr_prev: Khoảng cách nhịp trước đó (giây)
    """
    N        = len(signal)
    half     = N // 2
    
    # --- Tính toán thống kê cơ bản ---
    rms_val  = np.sqrt(np.mean(signal ** 2))
    peak_val = np.max(np.abs(signal))
    max_val  = np.max(signal)
    min_val  = np.min(signal)
    
    # 1. f_rms: Năng lượng tín hiệu
    f_rms   = float(rms_val)
    
    # 2. f_var: Phương sai (độ tản mát dữ liệu)
    f_var   = float(np.var(signal))
    
    # 3. f_peak: Đỉnh trị tuyệt đối lớn nhất
    f_peak  = float(peak_val)
    
    # 4. f_zc: Zero Crossing Rate (Tần số cắt đường 0)
    f_zc    = float(np.sum(np.diff(np.sign(signal)) != 0) / N)
    
    # 5. f_ptp: Peak-to-Peak (Biên độ đỉnh - đáy)
    f_ptp   = float(max_val - min_val)
    
    # 6. f_crest: Crest Factor (Phát hiện gai nhọn bất thường như PVC)
    # Clip [0, 15] để tránh giá trị vô cùng
    f_crest = float(np.clip(peak_val / (rms_val + 1e-9), 0.0, 15.0))
    
    # 7. f_half_ratio: So sánh năng lượng nửa đầu vs nửa sau (Sóng lệch)
    rms_h1 = np.sqrt(np.mean(signal[:half] ** 2))
    rms_h2 = np.sqrt(np.mean(signal[half:] ** 2))
    f_half_ratio = float(rms_h1 / (rms_h2 + 1e-9))
    
    # 8. f_max: Giá trị lớn nhất (giữ lại làm tham chiếu biên độ dương)
    f_max   = float(max_val)
    
    # --- CÁC ĐẶC TRƯNG MỚI (QUAN TRỌNG CHO LOẠN NHỊP) ---
    
    # 9. f_rr: Nhịp tim hiện tại
    f_rr    = float(rr_curr)
    
    # 10. f_rr_prev: Nhịp tim ngay trước đó (Memory)
    # Giúp AI so sánh được sự thay đổi
    f_rr_prev = float(rr_prev)
    
    # 11. f_rr_ratio: Tỷ lệ biến thiên (Current / Prev)
    # Nếu = 1.0: Bình thường. Nếu > 1.5 hoặc < 0.6: Rất có thể là Loạn nhịp
    f_rr_ratio = float(rr_curr / (rr_prev + 1e-9))
    
    # 12. f_rr_diff: Độ lệch tuyệt đối (Current - Prev)
    f_rr_diff = float(rr_curr - rr_prev)

    return [f_rms, f_var, f_peak, f_zc, f_ptp, f_crest, 
            f_half_ratio, f_max, 
            f_rr, f_rr_prev, f_rr_ratio, f_rr_diff]

# ==========================================
# LOGIC GÁN NHÃN (LABELING)
# ==========================================
def get_label(symbol, hr, rr_curr, rr_prev):
    # 1. Ưu tiên tuyệt đối: Annotation từ bác sĩ
    if symbol in arrhythmia_major or symbol in arrhythmia_minor:
        return 3 # Abnormal (Arrhythmia)
    
    # 2. Kiểm tra đột biến nhịp (Arrhythmia ẩn)
    # Nếu nhịp nhảy cóc quá 20% so với nhịp trước -> Bất thường
    if rr_prev > 0:
        change_pct = abs(rr_curr - rr_prev) / rr_prev
        if change_pct > 0.20: 
            return 3
            
    # 3. Dựa vào nhịp tim (Heart Rate)
    if hr < 60: return 2   # Slow (Bradycardia)
    if hr > 100: return 1  # Fast (Tachycardia)
    
    return 0 # Normal

# ==========================================
# MAIN PROCESS
# ==========================================
if __name__ == "__main__":
    print("=" * 50)
    print("BẮT ĐẦU TẠO DATASET VỚI CÁC ĐẶC TRƯNG MỚI")
    print(f"Resampling: {FS_ORIGINAL}Hz -> {FS_HARDWARE}Hz")
    print("=" * 50)
    
    dataset_rows = []
    ekg_files = glob.glob(os.path.join(folder_path, "*_ekg.csv"))
    
    count_files = 0
    
    for ekg_file in ekg_files:
        patient_id = os.path.basename(ekg_file).split('_')[0]
        anno_file  = os.path.join(folder_path, f"{patient_id}_annotations_1.csv")
        
        if not os.path.exists(anno_file): continue
        
        try:
            df_ekg = pd.read_csv(ekg_file)
            df_anno = pd.read_csv(anno_file)
        except: continue

        # Chọn cột tín hiệu (MLII > V5 > V2 > Cột 1)
        lead_cols = [c for c in df_ekg.columns if 'MLII' in c]
        if not lead_cols: lead_cols = [c for c in df_ekg.columns if 'V5' in c]
        if not lead_cols: lead_cols = [df_ekg.columns[1]] # Fallback
        
        lead_name = lead_cols[0]
        signal_full_360 = df_ekg[lead_name].values.astype(np.float32)
        
        # Lọc beat hợp lệ
        valid_beats = df_anno[df_anno['annotation_symbol'].isin(valid_symbols)].reset_index(drop=True)
        
        # Buffer lưu nhịp trước đó
        prev_rr_sec = 0.8 # Giá trị mặc định ban đầu (tương đương 75 BPM)
        
        for i in range(1, len(valid_beats)-1):
            idx = int(valid_beats.loc[i, 'index'])
            prev_idx_sample = int(valid_beats.loc[i-1, 'index'])
            sym = valid_beats.loc[i, 'annotation_symbol']
            
            # Tính RR interval (giây)
            rr_samples = idx - prev_idx_sample
            if rr_samples <= 0: continue
            
            rr_sec = rr_samples / FS_ORIGINAL
            hr = 60.0 / rr_sec
            
            # Cắt cửa sổ tại 360Hz
            start = idx - HALF_WINDOW
            end = idx + HALF_WINDOW
            
            # Bỏ qua nếu ra ngoài biên
            if start < 0 or end > len(signal_full_360): continue
            
            win_360 = signal_full_360[start:end]
            
            # === RESAMPLE VỀ 250HZ ===
            # Sử dụng scipy.signal.resample để chuyển đổi mượt mà
            win_250 = resample(win_360, WINDOW_RESAMPLED)
            
            # Trích xuất 12 đặc trưng (bao gồm RR history)
            feats = extract_12_features(win_250, rr_sec, prev_rr_sec)
            
            # Gán nhãn
            label = get_label(sym, hr, rr_sec, prev_rr_sec)
            
            dataset_rows.append([patient_id, hr, label] + feats)
            
            # Cập nhật nhịp cũ cho vòng lặp sau
            prev_rr_sec = rr_sec
            
        count_files += 1
        if count_files % 5 == 0:
            print(f"Processed {count_files} files...")

    # Lưu file CSV
    # Cập nhật tên cột theo đúng thứ tự mới
    feature_cols = [
        'f_rms', 'f_var', 'f_peak', 'f_zc', 'f_ptp', 'f_crest', 
        'f_half_ratio', 'f_max', 
        'f_rr', 'f_rr_prev', 'f_rr_ratio', 'f_rr_diff'
    ]
    
    cols = ['patient_id', 'hr', 'label'] + feature_cols
    
    out_file = "AI_Training_12_Features_250Hz_V2.csv"
    df_final = pd.DataFrame(dataset_rows, columns=cols)
    df_final.to_csv(out_file, index=False)
    
    print("\n" + "=" * 50)
    print("HOÀN TẤT!")
    print(f"File saved: {out_file}")
    print(f"Total samples: {len(df_final)}")
    print("Label Distribution:")
    print(df_final['label'].value_counts().sort_index())
    print("=" * 50)