import torch
import torch.nn as nn
import pandas as pd
import numpy as np
import os

# ==========================================
# CẤU HÌNH TÊN FILE (Kiểm tra kỹ tên file của bạn)
# ==========================================
MODEL_PATH  = "mlp_fpga_best.pth"       # File model tốt nhất bạn đã lưu
SCALER_PATH = "scaler_params_fpga.csv"  # File thông số chuẩn hóa
OUTPUT_HEX  = "weight.hex"     # Tên file Hex đầu ra

# ==========================================
# 1. ĐỊNH NGHĨA LẠI KIẾN TRÚC MẠNG (Phải giống hệt lúc train)
# ==========================================
class HeartRateNet(nn.Module):
    def __init__(self):
        super(HeartRateNet, self).__init__()
        self.fc1 = nn.Linear(12, 8)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(8, 4) 

    def forward(self, x):
        out = self.fc1(x)
        out = self.relu(out)
        out = self.fc2(out)
        return out

# ==========================================
# 2. HÀM CHUYỂN ĐỔI SANG HEX (Q4.12 FIXED POINT)
# ==========================================
def float_to_hex_q4_12(value):
    # Q4.12: 1 bit dấu, 3 bit nguyên, 12 bit thập phân
    # Scale factor = 2^12 = 4096
    scaled = int(value * 4096)
    
    # Kẹp giá trị (Clamp) trong khoảng 16-bit signed
    # Min: -32768, Max: 32767
    scaled = max(min(scaled, 32767), -32768)
    
    # Chuyển sang Hex 4 ký tự (Bù 2 - Two's Complement)
    return f"{scaled & 0xFFFF:04X}"

# ==========================================
# 3. CHƯƠNG TRÌNH CHÍNH
# ==========================================
if __name__ == "__main__":
    print(f"--- ĐANG ĐỌC FILE: {MODEL_PATH} và {SCALER_PATH} ---")
    
    # A. Kiểm tra file tồn tại
    if not os.path.exists(MODEL_PATH) or not os.path.exists(SCALER_PATH):
        print("LỖI: Không tìm thấy file .pth hoặc .csv!")
        exit()

    # B. Load Model Weights
    device = torch.device("cpu") # Chỉ cần CPU để xuất file
    model = HeartRateNet().to(device)
    model.load_state_dict(torch.load(MODEL_PATH, map_location=device))
    weights = model.state_dict()
    print("-> Đã load model thành công.")

    # C. Load Scaler Parameters
    df_scaler = pd.read_csv(SCALER_PATH)
    means = df_scaler['mean'].values
    scales = df_scaler['scale'].values
    inv_scales = 1.0 / scales # Tính nghịch đảo để FPGA dùng phép nhân
    print("-> Đã load scaler thành công.")

    # D. Ghi file Hex
    print(f"-> Đang ghi file {OUTPUT_HEX}...")
    
    with open(OUTPUT_HEX, "w") as f:
        # --- 1. Header: Scaler Params (24 dòng) ---
        # Ghi 12 Mean
        for val in means: f.write(float_to_hex_q4_12(val) + "\n")
        # Ghi 12 Inv_Scale
        for val in inv_scales: f.write(float_to_hex_q4_12(val) + "\n")
        
        # --- 2. Body: Model Weights (140 dòng) ---
        # Layer 1 Weights (96 dòng)
        w1 = weights['fc1.weight'].numpy().flatten()
        for val in w1: f.write(float_to_hex_q4_12(val) + "\n")
            
        # Layer 1 Biases (8 dòng)
        b1 = weights['fc1.bias'].numpy().flatten()
        for val in b1: f.write(float_to_hex_q4_12(val) + "\n")
            
        # Layer 2 Weights (32 dòng)
        w2 = weights['fc2.weight'].numpy().flatten()
        for val in w2: f.write(float_to_hex_q4_12(val) + "\n")
            
        # Layer 2 Biases (4 dòng)
        b2 = weights['fc2.bias'].numpy().flatten()
        for val in b2: f.write(float_to_hex_q4_12(val) + "\n")

    print("\n" + "="*50)
    print("XUẤT FILE THÀNH CÔNG!")
    print(f"File: {OUTPUT_HEX}")
    print("="*50)
    
    # E. In bản đồ địa chỉ để bạn code Verilog
    print("BẢN ĐỒ ĐỊA CHỈ ROM (ROM MEMORY MAP):")
    addr = 0
    print(f"[{addr:03d}-{addr+11:03d}] : Means (12 words)      -> Trừ đi giá trị này")
    addr += 12
    print(f"[{addr:03d}-{addr+11:03d}] : Inv_Scales (12 words) -> Nhân với giá trị này")
    addr += 12
    print("-" * 30)
    print(f"[{addr:03d}-{addr+95:03d}] : L1 Weights (96 words) -> Nhân chập lớp 1")
    addr += 96
    print(f"[{addr:03d}-{addr+7:03d}]  : L1 Biases (8 words)   -> Cộng bias lớp 1")
    addr += 8
    print(f"[{addr:03d}-{addr+31:03d}] : L2 Weights (32 words) -> Nhân chập lớp 2")
    addr += 32
    print(f"[{addr:03d}-{addr+3:03d}]  : L2 Biases (4 words)   -> Cộng bias lớp 2")
    print("-" * 30)
    print(f"TỔNG CỘNG: {addr + 4} dòng.")