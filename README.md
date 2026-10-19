# Olist E-commerce Analytics Web App

Ứng dụng Streamlit cho dự án Olist: dashboard, 14 truy vấn PostgreSQL, thử nghiệm ML (mua lại và RFM), đọc CSV/ZIP và tải kết quả.

## Chạy local
```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
streamlit run app.py
```

## Kết nối Supabase
Nhập `DATABASE_URL` ở sidebar hoặc cấu hình trong Streamlit Cloud → App settings → Secrets:
```toml
DATABASE_URL = "postgresql+psycopg://USER:PASSWORD@HOST:5432/postgres?sslmode=require"
```
Dùng user có quyền đọc dữ liệu. Không đưa mật khẩu vào Git.

## Deploy public
1. Push thư mục này lên GitHub.
2. Mở https://share.streamlit.io/ và chọn repository + `app.py`.
3. Thêm `DATABASE_URL` trong Secrets và deploy.
4. Khi deploy thành công, Streamlit Cloud cấp URL công khai.

Lưu ý: mã nguồn tạo được URL sau khi bạn thực hiện bước deploy trong tài khoản hosting; chưa có URL công khai cho đến khi deploy hoàn tất. ML là demo, cần đánh giá dữ liệu/metric trước khi dùng thực tế.
