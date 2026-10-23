# Olist E-commerce Analytics — bản cập nhật

## Thành phần
- `app.py`: Streamlit app; đã sửa lỗi cú pháp ở KPI đơn hủy và làm rõ giới hạn demo ML.
- `queries.py`: 14 truy vấn PostgreSQL cho câu hỏi nghiệp vụ.
- `14_truy_van_SQL_tham_khao.sql`: bộ SQL PostgreSQL.
- `Notebook_nguon_Olist.ipynb`: notebook nguồn; output của ô kết nối được làm sạch để tránh lưu thông tin phiên.
- `requirements.txt`: thư viện ứng dụng.

## Chạy local
```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
pip install -r requirements.txt
streamlit run app.py
```

## Kết nối Supabase
Cấu hình `DATABASE_URL` trong biến môi trường hoặc Streamlit Secrets:
```toml
DATABASE_URL = "postgresql+psycopg://USER:PASSWORD@HOST:5432/postgres?sslmode=require"
```
Không commit mật khẩu lên GitHub. Dùng tài khoản chỉ đọc nếu chỉ phân tích.

## Lưu ý về kết quả notebook
- Dữ liệu quan sát: 99.441 orders, 99.441 customers, 112.650 order items, 1.000.163 geolocation rows.
- Điểm review trung bình 4,09/5; tỷ lệ hủy đơn 0,63%.
- Mua lại toàn lịch sử: 3,04%; nhãn mua lại trong 90 ngày: 2,03% (khác định nghĩa).
- Mô hình mua lại: precision 0,0549 / recall 0,0518 / F1 0,0533 trên test.
- Dự báo Ridge có WAPE 47,24%; baseline tháng gần nhất tốt hơn với WAPE 37,55%.
- Các chỉ số là output notebook đã lưu, cần chạy lại nếu dữ liệu/bộ lọc thay đổi. Ứng dụng hiển thị chỉ số ML từ notebook thay vì huấn luyện lại mô hình mua lại có nguy cơ rò rỉ nhãn; RFM trong ứng dụng là demo khám phá.

## Triển khai
1. Đưa mã nguồn lên GitHub.
2. Mở Streamlit Community Cloud và chọn `app.py`.
3. Thêm `DATABASE_URL` vào Secrets.
4. Deploy. URL chỉ được cấp sau khi bạn thực hiện deploy bằng tài khoản hosting.
