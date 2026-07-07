import pandas as pd

# 1. Đọc file excel
df = pd.read_excel('features.xlsx')
#
df_features = df.iloc[:, 15:27]
# Tên các cột cần trích xuất

# 2. Ghi dữ liệu trải dọc xuống file text
with open('ket_qua_trich_xuat_doc.txt', 'w') as f:
    for index, row in df_features[:500].iterrows():
        for val in row:
            if pd.notna(val):
                f.write(str(val).strip() + "\n")

print("Đã trích xuất xong dạng một cột dọc!")