-- OLIST E-COMMERCE ANALYSIS — PostgreSQL edition
-- Bộ truy vấn viết lại theo 14 BUSINESS QUESTIONS trong README của bộ tài liệu.
-- Giả định các bảng nằm trong schema public và tên cột giống bộ dữ liệu Olist đã nhập.
-- Nếu bạn đã tạo schema olist, đổi tên bảng thành olist.<table> hoặc chạy: SET search_path TO olist, public;
-- PostgreSQL: dùng EXTRACT/DATE_TRUNC, LIMIT, COALESCE; không dùng DATEPART, TOP, ISNULL.
-- LƯU Ý: payment_value là giá trị thanh toán ở cấp payment; khi nối trực tiếp với order_items
-- một đơn có nhiều item sẽ nhân đôi payment. Các truy vấn theo danh mục/sản phẩm bên dưới
-- phân bổ doanh thu theo item.price + freight_value hoặc dùng giá trị item, tránh cộng lặp payment.

-- =========================================================
-- Q1. Tổng doanh thu và xu hướng theo tháng/quý
-- Định nghĩa doanh thu: tổng payment_value của đơn không bị hủy/không unavailable.
-- =========================================================
SELECT ROUND(SUM(p.payment_value)::numeric, 2) AS total_revenue_brl
FROM olist_orders_dataset o
JOIN olist_order_payments_dataset p USING (order_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable');

SELECT DATE_TRUNC('month', o.order_purchase_timestamp)::date AS month,
       ROUND(SUM(p.payment_value)::numeric, 2) AS revenue_brl
FROM olist_orders_dataset o
JOIN olist_order_payments_dataset p USING (order_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY 1 ORDER BY 1;

SELECT EXTRACT(YEAR FROM o.order_purchase_timestamp)::int AS year,
       EXTRACT(QUARTER FROM o.order_purchase_timestamp)::int AS quarter,
       ROUND(SUM(p.payment_value)::numeric, 2) AS revenue_brl
FROM olist_orders_dataset o
JOIN olist_order_payments_dataset p USING (order_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY 1, 2 ORDER BY 1, 2;

-- =========================================================
-- Q2. Số đơn hàng tổng cộng và biến động theo tháng/mùa
-- Một order_id được tính là một đơn, không đếm các dòng payment/item.
-- =========================================================
SELECT COUNT(*) AS total_orders
FROM olist_orders_dataset
WHERE order_status NOT IN ('canceled', 'unavailable');

SELECT DATE_TRUNC('month', order_purchase_timestamp)::date AS month,
       COUNT(*) AS order_count
FROM olist_orders_dataset
WHERE order_status NOT IN ('canceled', 'unavailable')
GROUP BY 1 ORDER BY 1;

SELECT EXTRACT(YEAR FROM order_purchase_timestamp)::int AS year,
       CASE
         WHEN EXTRACT(MONTH FROM order_purchase_timestamp) IN (12,1,2) THEN 'Summer (Dec-Feb)'
         WHEN EXTRACT(MONTH FROM order_purchase_timestamp) IN (3,4,5) THEN 'Autumn (Mar-May)'
         WHEN EXTRACT(MONTH FROM order_purchase_timestamp) IN (6,7,8) THEN 'Winter (Jun-Aug)'
         ELSE 'Spring (Sep-Nov)'
       END AS season_brazil,
       COUNT(*) AS order_count
FROM olist_orders_dataset
WHERE order_status NOT IN ('canceled', 'unavailable')
GROUP BY 1, 2 ORDER BY 1, 2;

-- =========================================================
-- Q3. Danh mục sản phẩm phổ biến và lượng bán
-- Dùng số lượng item và doanh thu hàng hóa (price); không cộng payment_value
-- sau khi join item vì payment bị lặp theo số item trong đơn.
-- =========================================================
SELECT COALESCE(p.product_category_name, 'unknown') AS category,
       SUM(oi.order_item_id * 0 + 1) AS item_lines,
       SUM(oi.price) AS merchandise_sales_brl,
       SUM(oi.freight_value) AS freight_brl,
       COUNT(DISTINCT oi.order_id) AS orders
FROM olist_order_items_dataset oi
JOIN olist_products_dataset p USING (product_id)
JOIN olist_orders_dataset o USING (order_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY 1 ORDER BY item_lines DESC;

-- =========================================================
-- Q4. AOV tổng thể, theo phương thức thanh toán và danh mục
-- Tổng thể AOV = tổng tiền thanh toán / số đơn; payment có nhiều installment
-- được cộng theo order trước để không xem mỗi dòng payment là một đơn.
-- =========================================================
WITH order_payment AS (
  SELECT order_id, SUM(payment_value) AS order_value
  FROM olist_order_payments_dataset GROUP BY order_id
)
SELECT ROUND(AVG(op.order_value)::numeric, 2) AS average_order_value_brl
FROM order_payment op
JOIN olist_orders_dataset o USING (order_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable');

SELECT p.payment_type,
       COUNT(DISTINCT p.order_id) AS orders,
       ROUND(AVG(p.order_payment)::numeric, 2) AS avg_order_value_brl
FROM (
  SELECT order_id, payment_type, SUM(payment_value) AS order_payment
  FROM olist_order_payments_dataset
  GROUP BY order_id, payment_type
) p
JOIN olist_orders_dataset o USING (order_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY p.payment_type ORDER BY avg_order_value_brl DESC;

-- Category AOV uses item value as a category-level proxy; an order with multiple
-- categories may appear in more than one category. Revenue allocated by item price.
SELECT COALESCE(p.product_category_name, 'unknown') AS category,
       COUNT(DISTINCT oi.order_id) AS orders,
       ROUND(SUM(oi.price)::numeric / NULLIF(COUNT(DISTINCT oi.order_id),0), 2) AS category_sales_per_order_brl,
       ROUND(SUM(oi.price)::numeric, 2) AS merchandise_sales_brl
FROM olist_order_items_dataset oi
JOIN olist_products_dataset p USING (product_id)
JOIN olist_orders_dataset o USING (order_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY 1 ORDER BY category_sales_per_order_brl DESC;

-- =========================================================
-- Q5. Số người bán hoạt động theo năm/quý
-- "Active" = có ít nhất một item trong đơn hợp lệ ở kỳ đó; đây không phải
-- số seller mới đăng ký, vì dữ liệu không có ngày đăng ký seller.
-- =========================================================
WITH seller_period AS (
  SELECT DATE_TRUNC('year', o.order_purchase_timestamp)::date AS period,
         COUNT(DISTINCT oi.seller_id) AS active_sellers
  FROM olist_orders_dataset o
  JOIN olist_order_items_dataset oi USING (order_id)
  WHERE o.order_status NOT IN ('canceled', 'unavailable')
  GROUP BY 1
)
SELECT period, active_sellers,
       active_sellers - LAG(active_sellers) OVER (ORDER BY period) AS change_vs_previous_period
FROM seller_period ORDER BY period;

WITH seller_period AS (
  SELECT DATE_TRUNC('quarter', o.order_purchase_timestamp)::date AS period,
         COUNT(DISTINCT oi.seller_id) AS active_sellers
  FROM olist_orders_dataset o
  JOIN olist_order_items_dataset oi USING (order_id)
  WHERE o.order_status NOT IN ('canceled', 'unavailable')
  GROUP BY 1
)
SELECT period, active_sellers,
       active_sellers - LAG(active_sellers) OVER (ORDER BY period) AS change_vs_previous_quarter
FROM seller_period ORDER BY period;

-- =========================================================
-- Q6. Phân phối điểm đánh giá và liên hệ với doanh thu
-- Review score là đánh giá của khách hàng về đơn hàng, không phải rating riêng của seller.
-- =========================================================
SELECT r.review_score,
       COUNT(DISTINCT r.review_id) AS review_count,
       COUNT(DISTINCT r.order_id) AS orders,
       ROUND(AVG(pay.order_value)::numeric, 2) AS avg_order_value_brl,
       ROUND(SUM(pay.order_value)::numeric, 2) AS order_payment_total_brl
FROM olist_order_reviews_dataset r
JOIN (
  SELECT order_id, SUM(payment_value) AS order_value
  FROM olist_order_payments_dataset GROUP BY order_id
) pay USING (order_id)
JOIN olist_orders_dataset o USING (order_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY r.review_score ORDER BY r.review_score DESC;

-- Correlation across individual orders between review score and order payment.
WITH per_order AS (
  SELECT o.order_id, AVG(r.review_score)::numeric AS review_score,
         SUM(p.payment_value)::numeric AS order_value
  FROM olist_orders_dataset o
  JOIN olist_order_reviews_dataset r USING (order_id)
  JOIN olist_order_payments_dataset p USING (order_id)
  WHERE o.order_status NOT IN ('canceled', 'unavailable')
  GROUP BY o.order_id
)
SELECT ROUND(CORR(review_score, order_value)::numeric, 3) AS pearson_correlation
FROM per_order;

-- =========================================================
-- Q7. Khách hàng mua lặp lại và tỷ trọng doanh thu
-- customer_unique_id là định danh khách hàng hợp lý hơn customer_id (mỗi đơn có thể
-- tạo customer_id khác nhau). Tính mỗi đơn một lần trước khi cộng doanh thu.
-- =========================================================
WITH customer_orders AS (
  SELECT c.customer_unique_id, o.order_id,
         COALESCE(pay.order_value, 0) AS order_value
  FROM olist_customers_dataset c
  JOIN olist_orders_dataset o USING (customer_id)
  LEFT JOIN (
    SELECT order_id, SUM(payment_value) AS order_value
    FROM olist_order_payments_dataset GROUP BY order_id
  ) pay USING (order_id)
  WHERE o.order_status NOT IN ('canceled', 'unavailable')
), customer_summary AS (
  SELECT customer_unique_id, COUNT(DISTINCT order_id) AS order_count,
         SUM(order_value) AS total_spent
  FROM customer_orders GROUP BY customer_unique_id
), totals AS (
  SELECT SUM(total_spent) AS total_revenue FROM customer_summary
)
SELECT COUNT(*) FILTER (WHERE cs.order_count > 1) AS repeat_customers,
       COUNT(*) AS unique_customers,
       COUNT(*) FILTER (WHERE cs.order_count = 1) AS one_time_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE cs.order_count > 1) / NULLIF(COUNT(*),0), 2) AS repeat_customer_rate_pct,
       ROUND(100.0 * SUM(cs.total_spent) FILTER (WHERE cs.order_count > 1) / NULLIF(MAX(t.total_revenue),0), 2) AS repeat_customer_revenue_pct
FROM customer_summary cs CROSS JOIN totals t;

-- =========================================================
-- Q8. Điểm đánh giá trung bình và hiệu suất bán hàng
-- =========================================================
SELECT ROUND(AVG(review_score)::numeric, 2) AS average_review_score,
       COUNT(*) AS review_rows,
       COUNT(*) FILTER (WHERE review_score IS NULL) AS missing_scores
FROM olist_order_reviews_dataset;

SELECT r.review_score,
       COUNT(DISTINCT o.order_id) AS orders,
       ROUND(SUM(pay.order_value)::numeric, 2) AS revenue_brl,
       ROUND(AVG(pay.order_value)::numeric, 2) AS average_order_value_brl
FROM olist_order_reviews_dataset r
JOIN olist_orders_dataset o USING (order_id)
JOIN (
  SELECT order_id, SUM(payment_value) AS order_value
  FROM olist_order_payments_dataset GROUP BY order_id
) pay USING (order_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY r.review_score ORDER BY r.review_score DESC;

-- =========================================================
-- Q9. Tỷ lệ hủy đơn và phân tích theo seller
-- Tỷ lệ hủy = số order canceled / tất cả order; không join payment để tránh nhân dòng.
-- "Doanh thu mất" không thể xác định chính xác chỉ từ payment của đơn hủy, vì payment
-- có thể tồn tại ở dữ liệu hủy/hoàn tiền. Truy vấn dưới đây báo số tiền ghi nhận gắn với
-- đơn hủy như một chỉ báo cần kiểm tra, không khẳng định là tổn thất thực.
-- =========================================================
SELECT COUNT(*) AS all_orders,
       COUNT(*) FILTER (WHERE order_status = 'canceled') AS canceled_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE order_status = 'canceled') / NULLIF(COUNT(*),0), 2) AS cancellation_rate_pct
FROM olist_orders_dataset;

SELECT oi.seller_id,
       COUNT(DISTINCT oi.order_id) AS orders_with_items,
       COUNT(DISTINCT oi.order_id) FILTER (WHERE o.order_status = 'canceled') AS canceled_orders,
       ROUND(100.0 * COUNT(DISTINCT oi.order_id) FILTER (WHERE o.order_status = 'canceled')
             / NULLIF(COUNT(DISTINCT oi.order_id),0), 2) AS cancellation_rate_pct,
       ROUND(SUM(oi.price) FILTER (WHERE o.order_status NOT IN ('canceled','unavailable'))::numeric, 2) AS valid_item_sales_brl
FROM olist_order_items_dataset oi
JOIN olist_orders_dataset o USING (order_id)
GROUP BY oi.seller_id
HAVING COUNT(DISTINCT oi.order_id) >= 5
ORDER BY cancellation_rate_pct DESC NULLS LAST
LIMIT 20;

-- =========================================================
-- Q10. Sản phẩm bán chạy nhất và xu hướng
-- Top products by units, revenue by item price, and monthly trend.
-- =========================================================
SELECT oi.product_id,
       COALESCE(p.product_category_name, 'unknown') AS category,
       COUNT(*) AS item_lines,
       SUM(oi.price) AS merchandise_sales_brl,
       COUNT(DISTINCT oi.order_id) AS orders
FROM olist_order_items_dataset oi
JOIN olist_products_dataset p USING (product_id)
JOIN olist_orders_dataset o USING (order_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY oi.product_id, 2
ORDER BY item_lines DESC, merchandise_sales_brl DESC
LIMIT 20;

SELECT DATE_TRUNC('month', o.order_purchase_timestamp)::date AS month,
       oi.product_id,
       COUNT(*) AS item_lines,
       ROUND(SUM(oi.price)::numeric, 2) AS merchandise_sales_brl
FROM olist_order_items_dataset oi
JOIN olist_orders_dataset o USING (order_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY 1, 2
ORDER BY 1, merchandise_sales_brl DESC;

-- =========================================================
-- Q11. Phương thức thanh toán phổ biến theo danh mục và địa lý
-- =========================================================
SELECT payment_type,
       COUNT(DISTINCT order_id) AS orders,
       ROUND(SUM(payment_value)::numeric, 2) AS payment_total_brl
FROM olist_order_payments_dataset
GROUP BY payment_type ORDER BY orders DESC;

SELECT p.payment_type,
       COALESCE(pr.product_category_name, 'unknown') AS category,
       COUNT(DISTINCT p.order_id) AS orders,
       COUNT(DISTINCT o.customer_id) AS customers
FROM olist_order_payments_dataset p
JOIN olist_orders_dataset o USING (order_id)
JOIN olist_order_items_dataset oi USING (order_id)
JOIN olist_products_dataset pr USING (product_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY 1, 2 ORDER BY orders DESC;

SELECT p.payment_type, c.customer_state,
       COUNT(DISTINCT p.order_id) AS orders,
       COUNT(DISTINCT o.customer_id) AS customers,
       ROUND(SUM(p.payment_value)::numeric, 2) AS payment_total_brl
FROM olist_order_payments_dataset p
JOIN olist_orders_dataset o USING (order_id)
JOIN olist_customers_dataset c USING (customer_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY 1, 2 ORDER BY orders DESC;

-- =========================================================
-- Q12. Ảnh hưởng của review/ratings tới doanh thu và hiệu suất sản phẩm
-- Kết quả mô tả mối liên hệ, không tự chứng minh quan hệ nhân quả.
-- =========================================================
SELECT CASE r.review_score
         WHEN 5 THEN 'Excellent' WHEN 4 THEN 'Very good' WHEN 3 THEN 'Good'
         WHEN 2 THEN 'Bad' WHEN 1 THEN 'Very bad' ELSE 'Unknown'
       END AS rating_label,
       r.review_score,
       COUNT(DISTINCT r.order_id) AS orders,
       COUNT(DISTINCT r.review_id) AS reviews,
       ROUND(SUM(pay.order_value)::numeric, 2) AS revenue_brl,
       ROUND(AVG(pay.order_value)::numeric, 2) AS average_order_value_brl
FROM olist_order_reviews_dataset r
JOIN olist_orders_dataset o USING (order_id)
JOIN (
  SELECT order_id, SUM(payment_value) AS order_value
  FROM olist_order_payments_dataset GROUP BY order_id
) pay USING (order_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY r.review_score ORDER BY r.review_score DESC;

-- Product-level rating and item sales (revenue measured by item price to avoid duplicated order payment).
SELECT oi.product_id,
       COALESCE(p.product_category_name, 'unknown') AS category,
       ROUND(AVG(r.review_score)::numeric, 2) AS avg_review_score,
       COUNT(DISTINCT oi.order_id) AS orders,
       COUNT(*) AS item_lines,
       ROUND(SUM(oi.price)::numeric, 2) AS merchandise_sales_brl
FROM olist_order_items_dataset oi
JOIN olist_products_dataset p USING (product_id)
JOIN olist_orders_dataset o USING (order_id)
LEFT JOIN olist_order_reviews_dataset r USING (order_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY oi.product_id, 2
HAVING COUNT(DISTINCT oi.order_id) >= 5
ORDER BY avg_review_score DESC NULLS LAST, merchandise_sales_brl DESC
LIMIT 50;

-- =========================================================
-- Q13. Danh mục có biên lợi nhuận cao nhất
-- Olist public dataset không có cost of goods/marketing/operating costs, nên không thể
-- tính lợi nhuận hoặc profit margin thực. Đây là proxy: doanh thu item, phí vận chuyển
-- và tỷ trọng freight trên item revenue; không gọi proxy này là lợi nhuận.
-- =========================================================
SELECT COALESCE(p.product_category_name, 'unknown') AS category,
       ROUND(SUM(oi.price)::numeric, 2) AS merchandise_revenue_brl,
       ROUND(SUM(oi.freight_value)::numeric, 2) AS freight_brl,
       ROUND(100.0 * SUM(oi.freight_value) / NULLIF(SUM(oi.price),0)::numeric, 2) AS freight_to_item_revenue_pct,
       COUNT(*) AS item_lines,
       COUNT(DISTINCT oi.order_id) AS orders
FROM olist_order_items_dataset oi
JOIN olist_products_dataset p USING (product_id)
JOIN olist_orders_dataset o USING (order_id)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY 1 ORDER BY merchandise_revenue_brl DESC;

-- =========================================================
-- Q14. Khu vực có mật độ khách hàng cao và tỷ lệ giữ chân theo địa lý
-- Retention proxy: tỷ lệ khách unique có >=2 đơn hợp lệ trong mỗi customer_state.
-- =========================================================
WITH customer_order_counts AS (
  SELECT c.customer_unique_id, c.customer_state,
         COUNT(DISTINCT o.order_id) AS order_count
  FROM olist_customers_dataset c
  JOIN olist_orders_dataset o USING (customer_id)
  WHERE o.order_status NOT IN ('canceled', 'unavailable')
  GROUP BY c.customer_unique_id, c.customer_state
)
SELECT customer_state,
       COUNT(*) AS unique_customers,
       COUNT(*) FILTER (WHERE order_count > 1) AS repeat_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE order_count > 1) / NULLIF(COUNT(*),0), 2) AS retention_rate_pct,
       ROUND(AVG(order_count)::numeric, 2) AS avg_orders_per_customer
FROM customer_order_counts
GROUP BY customer_state
ORDER BY unique_customers DESC;

-- Customer density by city/state. This is customer counts, not population-normalized density.
SELECT customer_state, customer_city, COUNT(DISTINCT customer_unique_id) AS unique_customers
FROM olist_customers_dataset
GROUP BY customer_state, customer_city
ORDER BY unique_customers DESC
LIMIT 50;

-- =========================================================
-- DATA QUALITY CHECKS (run before interpreting results)
-- =========================================================
SELECT 'orders' AS table_name, COUNT(*) AS row_count FROM olist_orders_dataset
UNION ALL SELECT 'order_items', COUNT(*) FROM olist_order_items_dataset
UNION ALL SELECT 'payments', COUNT(*) FROM olist_order_payments_dataset
UNION ALL SELECT 'reviews', COUNT(*) FROM olist_order_reviews_dataset
UNION ALL SELECT 'products', COUNT(*) FROM olist_products_dataset
UNION ALL SELECT 'customers', COUNT(*) FROM olist_customers_dataset
UNION ALL SELECT 'sellers', COUNT(*) FROM olist_sellers_dataset;

-- Check duplicate order ids and missing category names
SELECT order_id, COUNT(*) AS rows_per_order
FROM olist_orders_dataset GROUP BY order_id HAVING COUNT(*) > 1;

SELECT COUNT(*) AS products_without_category
FROM olist_products_dataset
WHERE product_category_name IS NULL;
