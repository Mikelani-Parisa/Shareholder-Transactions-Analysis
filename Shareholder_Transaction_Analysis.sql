-- ###############################################
-- پروژه SQL: تحلیل معاملات سهام شرکت بازارگردان
-- هدف: محاسبه ارزش تجمعی، نرخ هر سهم و سود/زیان معاملات
-- نویسنده: Parisa Mikelani
-- ###############################################

-- پاک کردن جدول‌های موقت قبلی در صورت وجود
DROP TABLE IF EXISTS ##Transaction;
DROP TABLE IF EXISTS #DealsTemp;

-- مرحله 1: ایجاد جدول اصلی معاملات
CREATE TABLE ##Transaction (
    WarningDate CHAR(8),
    Qty MONEY,
    Amount MONEY,
    Sign_Deal INT,
    diff_date INT
);

-- Optional: درج یک ردیف اولیه در صورت نیاز
INSERT INTO ##Transaction (WarningDate, Qty, Amount, Sign_Deal, diff_date)
VALUES ('14040101', 308014, 50587946.946, 1, 0);

-- مرحله 2: جمع‌بندی معاملات سهامدار
;WITH T0 AS (
    SELECT 
        WarningDate,
        Qty,
        Amount,
        CASE 
            WHEN Qty > 0 THEN 1 ---خرید
            WHEN Qty < 0 THEN -1 ---- فروش
        END AS Sign_Deal
    FROM saham.vwShareHolder v
    WHERE ShareHolderNo = 9343 -- شماره سهامدار شرکت بازارگردان
      AND WarningDate BETWEEN 14040101 AND 14041229 --- بازه زمانی مورد نظر
),
T_Aggregated AS (
    SELECT
        WarningDate,
        SUM(Qty) AS Qty,
        SUM(Amount) AS Amount,
        Sign_Deal
    FROM T0
    GROUP BY WarningDate, Sign_Deal
)
INSERT INTO ##Transaction
SELECT 
    e.WarningDate,
    e.Qty,
    e.Amount,
    e.Sign_Deal,
    DATEDIFF(day, CONVERT(date, d.miladidate), '2026-03-20') AS diff_date
    -- تبدیل تاریخ‌های شمسی به میلادی با جدول dimdate
    -- محاسبه تعداد روزهای تا پایان سال میلادی با DATEDIFF
FROM T_Aggregated e
INNER JOIN dimdate d
    ON d.persiafull = e.WarningDate
ORDER BY WarningDate, Sign_Deal;

-- مرحله 3: ایجاد جدول موقت برای محاسبات تجمعی
CREATE TABLE #DealsTemp (
    rn INT,
    WarningDate CHAR(8),
    Qty MONEY,
    Amount MONEY,
    Sign_Deal INT,
    diff_date INT,
    rate FLOAT NULL,           -- نرخ هر سهم
    value_buy_sale FLOAT NULL, -- بهای خرید/فروش هر ردیف
    cum_value FLOAT NULL,      -- ارزش تجمعی سهام
    cum_qty FLOAT NULL         -- تعداد تجمعی سهام
);

INSERT INTO #DealsTemp
SELECT 
    ROW_NUMBER() OVER (ORDER BY WarningDate) AS rn,
    WarningDate,
    Qty,
    Amount,
    Sign_Deal,
    diff_date,
    NULL, NULL, NULL, NULL
FROM ##Transaction;

-- مرحله 4: محاسبه نرخ، ارزش تجمعی و سود/زیان
DECLARE 
    @i INT = 1,
    @max INT,
    @prev_rate FLOAT = NULL,
    @cum_value_buy FLOAT = 0,
    @value_buy_sale FLOAT,
    @cum_qty_buy FLOAT = 0,
    @amount FLOAT,
    @qty FLOAT,
    @sign INT,
    @rate FLOAT;

SELECT @max = MAX(rn) FROM #DealsTemp;

WHILE @i <= @max
BEGIN
    SELECT 
        @amount = Amount,
        @qty = Qty,
        @sign = Sign_Deal
    FROM #DealsTemp 
    WHERE rn = @i;

    IF @sign = 1 -- خرید
    BEGIN
        SET @cum_value_buy += @amount;
        SET @cum_qty_buy += @qty;
        SET @value_buy_sale = @amount;
        SET @rate = @cum_value_buy / NULLIF(@cum_qty_buy, 0);
    END
    ELSE -- فروش
    BEGIN
        SET @rate = ISNULL(@prev_rate, 0);
        SET @cum_value_buy += @qty * @rate;
        SET @value_buy_sale = @qty * @rate;
        SET @cum_qty_buy += @qty;
    END

    -- ذخیره مقادیر محاسبه شده در جدول موقت
    UPDATE #DealsTemp
    SET rate = @rate,
        cum_value = @cum_value_buy,
        cum_qty = @cum_qty_buy,
        value_buy_sale = @value_buy_sale
    WHERE rn = @i;

    SET @prev_rate = @rate;
    SET @i += 1;
END

-- مرحله 5: خروجی نهایی با محاسبه سود/زیان
SELECT 
    rn AS [ردیف],
    WarningDate AS [تاریخ],
	RIGHT(LEFT(WarningDate,6),2) AS [ماه],
    Qty AS [تعداد],
    Amount AS [مبلغ],
	Sign_Deal AS [نوع معامله],
	diff_date AS [تعداد روز تا پایان سال],
    rate AS [نرخ ],
	cum_value AS [بهای تمام شده تجمعی],
    cum_qty AS [تعداد تجمعی],
    CASE WHEN Sign_Deal = -1 THEN Amount - value_buy_sale ELSE 0 END AS [سودوزیان],
    CASE WHEN Sign_Deal = 1 THEN (diff_date * Qty)/365 ELSE 0 END AS [میانگین ],
	value_buy_sale AS [بهای تمام شده]
    
FROM #DealsTemp
ORDER BY rn;

