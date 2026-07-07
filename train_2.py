import torch
import torch.nn as nn
import torch.optim as optim
import pandas as pd
import numpy as np
import os
import matplotlib.pyplot as plt # THÊM: Thư viện vẽ đồ thị
import seaborn as sns           # THÊM: Thư viện vẽ Heatmap đẹp
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix # THÊM: Confusion Matrix
from torch.utils.data import DataLoader, TensorDataset

# ==========================================
# CẤU HÌNH TRAINING (ĐÃ CẬP NHẬT CHO DATASET V2)
# ==========================================
CSV_FILE    = "AI_Training_12_Features_250Hz_V2.csv"
MODEL_FILE  = "mlp_fpga_best.pth"
BATCH_SIZE  = 64    
MAX_EPOCHS  = 250   
LR          = 0.003 

# Thiết bị (GPU/CPU)
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Using device: {device}")

# ==========================================
# 1. LOAD & CHUẨN BỊ DATA
# ==========================================
if not os.path.exists(CSV_FILE):
    raise FileNotFoundError(f"Không tìm thấy file {CSV_FILE}. Hãy chạy file create_dataset.py trước!")

df = pd.read_csv(CSV_FILE)

# Tự động lấy tất cả các cột bắt đầu bằng 'f_'
feature_cols = [c for c in df.columns if c.startswith('f_')]
print(f"Features detected ({len(feature_cols)}): {feature_cols}")

X = df[feature_cols].values
y = df['label'].values

# Chia tập Train/Val/Test (70/15/15)
X_train, X_temp, y_train, y_temp = train_test_split(X, y, test_size=0.3, stratify=y, random_state=42)
X_val, X_test, y_val, y_test = train_test_split(X_temp, y_temp, test_size=0.5, stratify=y_temp, random_state=42)

# Chuẩn hóa
scaler = StandardScaler()
X_train = scaler.fit_transform(X_train)
X_val   = scaler.transform(X_val)
X_test  = scaler.transform(X_test)

# Lưu thông số scaler cho FPGA
params = pd.DataFrame({'mean': scaler.mean_, 'scale': scaler.scale_})
params.to_csv("scaler_params_fpga.csv", index=False)
print("Saved scaler params to 'scaler_params_fpga.csv'.")

# Chuyển sang Tensor
X_train_t = torch.FloatTensor(X_train).to(device)
y_train_t = torch.LongTensor(y_train).to(device)
X_val_t   = torch.FloatTensor(X_val).to(device)
y_val_t   = torch.LongTensor(y_val).to(device)
X_test_t  = torch.FloatTensor(X_test).to(device)
y_test_t  = torch.LongTensor(y_test).to(device)

# Tạo DataLoader
train_loader = DataLoader(TensorDataset(X_train_t, y_train_t), batch_size=BATCH_SIZE, shuffle=True)

# ==========================================
# 2. ĐỊNH NGHĨA MODEL 12-8-4
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

model = HeartRateNet().to(device)

# ==========================================
# 3. CLASS WEIGHTS & OPTIMIZER
# ==========================================
# Normal(0), Fast(1), Slow(2), Abnormal(3)
class_weights_t = torch.FloatTensor([1.0, 1.5, 1.5, 3.0]).to(device)
criterion = nn.CrossEntropyLoss(weight=class_weights_t)
optimizer = optim.Adam(model.parameters(), lr=LR, weight_decay=1e-4)
scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode='max', factor=0.5, patience=15)

# ==========================================
# 4. TRAINING LOOP
# ==========================================
# --- KHỞI TẠO LIST ĐỂ LƯU LỊCH SỬ (DÙNG ĐỂ VẼ BIỂU ĐỒ) ---
history = {
    'train_loss': [], 'val_loss': [],
    'train_acc': [], 'val_acc': [], 'test_acc': []
}

best_acc = 0.0
print(f"\nStarting training for {MAX_EPOCHS} epochs...")
patience = 20        # Số epoch chấp nhận "không tiến bộ" trước khi dừng
counter = 0          # Bộ đếm số lần không tiến bộ
best_val_loss = float('inf') # Khởi tạo loss thấp nhất là vô cùng

for epoch in range(MAX_EPOCHS):
    model.train()
    running_loss = 0.0
    correct = 0
    total = 0
    
    for inputs, labels in train_loader:
        optimizer.zero_grad()
        outputs = model(inputs)
        loss = criterion(outputs, labels)
        loss.backward()
        optimizer.step()
        
        running_loss += loss.item()
        _, predicted = torch.max(outputs.data, 1)
        total += labels.size(0)
        correct += (predicted == labels).sum().item()
        
    epoch_loss = running_loss / len(train_loader)
    epoch_acc = 100 * correct / total
    
    # Validation
    model.eval()
    val_loss_running = 0.0
    correct_val = 0
    total_val = 0
    with torch.no_grad():
        # A. tinh val acc và val loss
        outputs_val = model(X_val_t)
        loss_val = criterion(outputs_val, y_val_t) # Tính thêm Val Loss
        val_loss_running = loss_val.item()
        
        _, predicted_val = torch.max(outputs_val.data, 1)
        total_val += y_val_t.size(0)
        correct_val = (predicted_val == y_val_t).sum().item()
        # B. tính test acc mỗi epoch (để theo dõi, không dùng để lưu model)
        outputs_test = model(X_test_t)
        _, predicted_test = torch.max(outputs_test.data, 1)
        test_acc = 100 * (predicted_test == y_test_t).sum().item() / y_test_t.size(0)
    val_acc = 100 * correct_val / total_val
    
    # --- LƯU VÀO HISTORY ---
    history['train_loss'].append(epoch_loss)
    history['val_loss'].append(val_loss_running)
    history['train_acc'].append(epoch_acc)
    history['val_acc'].append(val_acc)
    history['test_acc'].append(test_acc)
    # Scheduler step
    scheduler.step(val_acc)
    
    # Save best model
    if val_acc > best_acc:
        best_acc = val_acc
    
    if (epoch + 1) % 10 == 0 or epoch == MAX_EPOCHS - 1:
        print(f"Epoch {epoch+1:03d} | Loss: {epoch_loss:.4f} | Train Acc: {epoch_acc:.2f}% | Val Acc: {val_acc:.2f}% | Test Acc: {test_acc:.2f}% | Best: {best_acc:.2f}%")

    
        
        
print(f"\nTraining Complete. Best Val Acc: {best_acc:.2f}%")

# ==========================================
# 5. ĐÁNH GIÁ & VẼ BIỂU ĐỒ (QUAN TRỌNG GỬI THẦY)
# ==========================================
print("\n" + "="*30)
print("EVALUATION & VISUALIZATION")
print("="*30)

# Load best model
model.load_state_dict(torch.load(MODEL_FILE))
model.eval()

# Dự đoán trên tập Test
with torch.no_grad():
    outputs = model(X_test_t)
    _, preds = torch.max(outputs, 1)

# Chuyển về CPU numpy để vẽ và báo cáo
y_true_np = y_test
y_pred_np = preds.cpu().numpy()
class_names = ['Normal', 'Fast', 'Slow', 'Abnormal']

# --- VẼ BIỂU ĐỒ 1: LOSS & ACCURACY ---
plt.figure(figsize=(14, 5))

# Subplot 1: Accuracy
plt.subplot(1, 2, 1)
plt.plot(history['train_acc'], label='Train Acc')
plt.plot(history['val_acc'], label='Val Acc')
plt.title('Training and Validation Accuracy')
plt.xlabel('Epochs')
plt.ylabel('Accuracy (%)')
plt.legend()
plt.grid(True)

# Subplot 2: Loss
plt.subplot(1, 2, 2)
plt.plot(history['train_loss'], label='Train Loss')
plt.plot(history['val_loss'], label='Val Loss')
plt.title('Training and Validation Loss')
plt.xlabel('Epochs')
plt.ylabel('Loss')
plt.legend()
plt.grid(True)

plt.tight_layout()
plt.savefig("Training_Curves.png") # Lưu ảnh
print("Saved chart: Training_Curves.png")
plt.show()

# --- VẼ BIỂU ĐỒ 2: CONFUSION MATRIX ---
cm = confusion_matrix(y_true_np, y_pred_np)
plt.figure(figsize=(8, 6))
sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', 
            xticklabels=class_names, yticklabels=class_names)
plt.ylabel('Thực tế (True Label)')
plt.xlabel('Dự đoán (Predicted Label)')
plt.title('Confusion Matrix - Kết quả kiểm thử')
plt.savefig("Confusion_Matrix.png") # Lưu ảnh
print("Saved chart: Confusion_Matrix.png")
plt.show()

# --- XUẤT BÁO CÁO CHI TIẾT ---
print("\nBÁO CÁO CHI TIẾT (Classification Report):")
print(classification_report(y_true_np, y_pred_np, target_names=class_names, digits=4))

# ==========================================
# 6. XUẤT HEX CHO FPGA
# ==========================================
