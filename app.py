import os, io, zipfile
import streamlit as st
import pandas as pd
import numpy as np
import plotly.express as px
from sqlalchemy import create_engine, text
from sklearn.model_selection import train_test_split
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.impute import SimpleImputer
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.cluster import KMeans
from sklearn.metrics import accuracy_score, classification_report, mean_absolute_error
from queries import QUERIES

st.set_page_config(page_title='Olist Analytics', page_icon='🛒', layout='wide')
st.title('🛒 Olist E-commerce Analytics')
st.caption('Dashboard • PostgreSQL/Supabase • 14 câu hỏi nghiệp vụ • Machine Learning • Xuất dữ liệu')

with st.sidebar:
    st.header('Kết nối dữ liệu')
    st.write('Có thể kết nối Supabase PostgreSQL hoặc tải CSV Olist để phân tích nhanh.')
    db_url = st.text_input('DATABASE_URL (hoặc cấu hình Secrets)', value=os.getenv('DATABASE_URL',''), type='password', help='Dùng URI PostgreSQL của Supabase. Khuyến nghị lưu trong Streamlit Secrets, không commit mật khẩu lên GitHub.')
    connect = st.button('Kết nối Supabase', type='primary')
    if connect and db_url:
        try:
            eng=create_engine(db_url, pool_pre_ping=True, connect_args={'sslmode':'require'})
            with eng.connect() as con: con.execute(text('SELECT 1'))
            st.session_state['engine_url']=db_url
            st.success('Kết nối thành công')
        except Exception as e: st.error(f'Kết nối thất bại: {e}')
    st.divider()
    uploaded=st.file_uploader('Tải lên ZIP chứa CSV hoặc một CSV', type=['zip','csv'])

@st.cache_data(show_spinner=False)
def read_upload(file_bytes, name):
    out={}
    if name.lower().endswith('.zip'):
        with zipfile.ZipFile(io.BytesIO(file_bytes)) as z:
            for n in z.namelist():
                if n.lower().endswith('.csv') and not n.startswith('__MACOSX/'):
                    key=os.path.basename(n).replace('.csv','')
                    try: out[key]=pd.read_csv(z.open(n), low_memory=False)
                    except Exception: pass
    else:
        out[os.path.basename(name).replace('.csv','')]=pd.read_csv(io.BytesIO(file_bytes),low_memory=False)
    return out

if uploaded:
    try:
        st.session_state['csv_data']=read_upload(uploaded.getvalue(),uploaded.name)
        st.sidebar.success(f"Đã đọc {len(st.session_state['csv_data'])} tệp/bảng CSV")
    except Exception as e: st.sidebar.error(f'Không đọc được tệp: {e}')

engine=None
if st.session_state.get('engine_url'):
    try: engine=create_engine(st.session_state['engine_url'],pool_pre_ping=True,connect_args={'sslmode':'require'})
    except Exception: engine=None
csv_data=st.session_state.get('csv_data',{})

def get_df(table):
    if engine is not None:
        return pd.read_sql_query(text(f'SELECT * FROM "{table}" LIMIT 200000'),engine)
    aliases={k.lower():v for k,v in csv_data.items()}
    return aliases.get(table.lower())

pages=st.tabs(['📊 Dashboard','🧮 14 truy vấn SQL','🤖 Machine Learning','📁 Dữ liệu & tải kết quả','🚀 Triển khai'])
with pages[0]:
    st.subheader('Tổng quan dữ liệu')
    if engine:
        st.success('Đang dùng Supabase PostgreSQL')
        try:
            tables=pd.read_sql_query(text("SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY table_name"),engine)
            st.metric('Số bảng trong public',len(tables)); st.dataframe(tables,use_container_width=True)
        except Exception as e: st.warning(f'Không đọc được danh sách bảng: {e}')
    elif csv_data:
        names=list(csv_data)
        c1,c2,c3=st.columns(3); c1.metric('Số CSV đã tải',len(names)); c2.metric('Tổng số dòng',sum(len(x) for x in csv_data.values())); c3.metric('Tổng số cột',sum(len(x.columns) for x in csv_data.values()))
        selected=st.selectbox('Chọn bảng CSV xem trước',names)
        df=csv_data[selected]; st.write(f'{len(df):,} dòng × {len(df.columns)} cột'); st.dataframe(df.head(100),use_container_width=True)
        st.download_button('Tải CSV đã chọn',df.to_csv(index=False).encode('utf-8-sig'),file_name=f'{selected}.csv',mime='text/csv')
    else:
        st.info('Kết nối Supabase ở thanh bên hoặc tải ZIP/CSV Olist để bắt đầu.')
    # Dashboard from uploaded raw tables where possible
    orders=get_df('olist_orders_dataset'); payments=get_df('olist_order_payments_dataset')
    if orders is not None:
        orders=orders.copy()
        if 'order_purchase_timestamp' in orders: orders['order_purchase_timestamp']=pd.to_datetime(orders['order_purchase_timestamp'],errors='coerce')
        a,b=st.columns(2); a.metric('Tổng đơn hàng',f'{orders.order_id.nunique():,}' if 'order_id' in orders else f'{len(orders):,}')
        if 'order_status' in orders: b.metric("Đơn đã hủy", f"{(orders.order_status == 'canceled').sum():,}")
        if 'order_purchase_timestamp' in orders:
            monthly=orders.dropna(subset=['order_purchase_timestamp']).assign(month=lambda x:x.order_purchase_timestamp.dt.to_period('M').astype(str)).groupby('month').size().rename('orders').reset_index()
            st.plotly_chart(px.line(monthly,x='month',y='orders',title='Số đơn theo tháng'),use_container_width=True)
    if payments is not None and 'payment_value' in payments:
        payments=payments.copy(); payments['payment_value']=pd.to_numeric(payments.payment_value,errors='coerce')
        st.metric('Tổng giá trị thanh toán (BRL)',f"{payments.payment_value.sum():,.2f}")
        if 'payment_type' in payments:
            pay=payments.groupby('payment_type',dropna=False).payment_value.sum().reset_index()
            st.plotly_chart(px.bar(pay,x='payment_type',y='payment_value',title='Giá trị thanh toán theo phương thức'),use_container_width=True)

with pages[1]:
    st.subheader('14 câu hỏi nghiệp vụ')
    st.caption('SQL chỉ chạy khi đã kết nối Supabase. Tên bảng/cột cần khớp schema Olist của bạn.')
    if not QUERIES: st.warning('Không tìm thấy truy vấn trong Notebook nguồn.')
    else:
        labels=[x[0] for x in QUERIES]
        chosen=st.selectbox('Chọn câu hỏi',labels)
        sql=next(q for title,q in QUERIES if title==chosen)
        st.code(sql,language='sql')
        if st.button('Chạy truy vấn',key='run_query'):
            if engine is None: st.error('Hãy kết nối Supabase ở thanh bên trước.')
            else:
                try:
                    result=pd.read_sql_query(text(sql),engine); st.session_state['last_result']=result; st.session_state['last_result_name']=chosen
                    st.success(f'Truy vấn trả về {len(result):,} dòng'); st.dataframe(result,use_container_width=True)
                except Exception as e: st.error(f'Truy vấn lỗi: {e}')
        if st.session_state.get('last_result') is not None:
            res=st.session_state['last_result']; st.download_button('Tải kết quả truy vấn CSV',res.to_csv(index=False).encode('utf-8-sig'),file_name='ket_qua_truy_van.csv',mime='text/csv')

with pages[2]:
    st.subheader('Thử nghiệm Machine Learning')
    st.warning('Đây là demo nhanh trên dữ liệu đang tải; không tương đương pipeline ML đã đánh giá theo thời gian trong notebook. Với nhãn mua lại hiếm, accuracy đơn lẻ có thể gây hiểu nhầm.')
    st.markdown('#### Dự đoán khách hàng mua lại')
    st.info(
        'Kết quả đánh giá theo thời gian của notebook nguồn: nhãn mua lại trong 90 ngày có tỷ lệ dương 2,03%; '
        'trên tập test, precision = 0,0549, recall = 0,0518, F1 = 0,0533, ROC-AUC = 0,5506 và PR-AUC = 0,0231. '
        'Baseline luôn dự đoán không mua lại đạt accuracy 0,9834. Vì nhãn rất mất cân bằng, accuracy không đủ '
        'để đánh giá mô hình. Không huấn luyện lại mô hình demo dùng tổng số đơn làm đặc trưng vì có nguy cơ rò rỉ nhãn.'
    )
    st.caption('Muốn tái lập thí nghiệm mua lại, hãy chạy phần Mô hình 1 trong Notebook_nguon_Olist.ipynb.')
    st.markdown('#### Phân khúc RFM bằng K-Means')
    # Nạp bảng customers rõ ràng trong tab ML; trước đây biến này chưa được khởi tạo,
    # gây NameError khi Streamlit chạy đến phần phân khúc RFM.
    customers = get_df('olist_customers_dataset')
    if customers is not None and orders is not None and 'customer_id' in customers.columns and {'customer_id','order_id','order_purchase_timestamp'}.issubset(orders.columns):
        o=orders.copy(); o['order_purchase_timestamp']=pd.to_datetime(o.order_purchase_timestamp,errors='coerce')
        d=o.merge(customers[['customer_id','customer_unique_id']],on='customer_id',how='left').dropna(subset=['customer_unique_id','order_purchase_timestamp'])
        ref=d.order_purchase_timestamp.max(); r=d.groupby('customer_unique_id').agg(recency=('order_purchase_timestamp',lambda s:(ref-s.max()).days),frequency=('order_id','nunique')).reset_index()
        if payments is not None and 'payment_value' in payments:
            p=payments.copy(); p['payment_value']=pd.to_numeric(p.payment_value,errors='coerce'); val=o[['order_id','customer_id']].merge(p.groupby('order_id',as_index=False).payment_value.sum(),on='order_id',how='left').merge(customers[['customer_id','customer_unique_id']],on='customer_id',how='left').groupby('customer_unique_id').payment_value.sum().rename('monetary').reset_index(); r=r.merge(val,on='customer_unique_id',how='left')
        else: r['monetary']=0
        if len(r)>=10:
            feats=r[['recency','frequency','monetary']].fillna(0); scaled=StandardScaler().fit_transform(np.log1p(feats.clip(lower=0)))
            k=st.slider('Số cụm K',2,8,4); r['cluster']=KMeans(n_clusters=k,random_state=42,n_init=10).fit_predict(scaled)
            st.dataframe(r.groupby('cluster')[['recency','frequency','monetary']].mean().round(2),use_container_width=True)
            st.plotly_chart(px.scatter(r.sample(min(5000,len(r)),random_state=42),x='recency',y='monetary',color='cluster',title='Phân khúc khách hàng RFM'),use_container_width=True)
            st.download_button('Tải kết quả RFM',r.to_csv(index=False).encode('utf-8-sig'),file_name='olist_rfm_clusters.csv',mime='text/csv')
        else: st.info('Chưa đủ khách hàng để phân cụm.')

with pages[3]:
    st.subheader('Dữ liệu và tải kết quả')
    if csv_data:
        for name,df in csv_data.items():
            with st.expander(f'{name} — {len(df):,} dòng, {len(df.columns)} cột'):
                st.write('Cột:',', '.join(map(str,df.columns))); st.dataframe(df.head(10),use_container_width=True)
                st.download_button(f'Tải {name}.csv',df.to_csv(index=False).encode('utf-8-sig'),file_name=f'{name}.csv',mime='text/csv',key='dl_'+name)
        buf=io.BytesIO()
        with zipfile.ZipFile(buf,'w',zipfile.ZIP_DEFLATED) as z:
            for name,df in csv_data.items(): z.writestr(f'{name}.csv',df.to_csv(index=False).encode('utf-8-sig'))
        st.download_button('Tải tất cả bảng CSV thành ZIP',buf.getvalue(),file_name='olist_csv_export.zip',mime='application/zip')
    if st.session_state.get('last_result') is not None:
        st.write('Kết quả truy vấn gần nhất'); st.dataframe(st.session_state['last_result'],use_container_width=True)
        st.download_button('Tải kết quả gần nhất',st.session_state['last_result'].to_csv(index=False).encode('utf-8-sig'),file_name='ket_qua.csv',mime='text/csv',key='lastdl')

with pages[4]:
    st.subheader('Đưa ứng dụng lên Internet')
    st.markdown("""1. Giải nén gói ZIP và đưa các file lên một GitHub repository riêng tư hoặc công khai (không chứa mật khẩu).\n2. Vào **Streamlit Community Cloud**, chọn **Deploy an app**, kết nối repository và chọn `app.py`.\n3. Trong **App settings → Secrets**, thêm cấu hình sau (thay bằng thông tin Supabase của bạn):\n\n```toml\nDATABASE_URL = "postgresql+psycopg://USER:PASSWORD@HOST:5432/postgres?sslmode=require"\n```\n\n4. Bấm Deploy. Sau khi build thành công, nền tảng sẽ cấp URL dạng `https://ten-app.streamlit.app`.\n\n**Bảo mật:** không đặt thông tin kết nối trong mã nguồn hoặc commit `.streamlit/secrets.toml`. Nếu database có dữ liệu nhạy cảm, giới hạn quyền user chỉ đọc và cân nhắc bảo vệ ứng dụng bằng xác thực.""")
    st.info('Ứng dụng đã được chuẩn bị để triển khai; chưa thể tạo URL công khai từ phiên này vì cần bạn kết nối tài khoản hosting và cấu hình bí mật Supabase.')
