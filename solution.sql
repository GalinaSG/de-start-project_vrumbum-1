-- Этап 1. Создание и заполнение БД
/* Создать схему raw_data */
CREATE SCHEMA IF NOT EXISTS raw_data;

/* Создать таблицу sales в схеме raw_data */
CREATE TABLE IF NOT EXISTS raw_data.sales (
    id INTEGER PRIMARY KEY,
    auto TEXT,
    gasoline_consumption NUMERIC(3,1) NULL,
    price NUMERIC(9,2),
    date DATE,
    person TEXT, 
    phone TEXT,
    discount INTEGER,
    brand_origin TEXT
);

/* Заполнить таблицу sales данными */
\copy raw_data.sales(id, auto, gasoline_consumption, price, date, person, phone, discount, brand_origin) FROM 'C:\temp\cars.csv' CSV HEADER NULL ‘null’; 

/* Создать схему car_shop, а в ней cоздать нормализованные таблицы */
/* Создать схему car_shop */
CREATE SCHEMA IF NOT EXISTS car_shop;

/* Создать таблицы в схеме car_shop */

/* Создать таблицу brands – бренды */
CREATE TABLE car_shop.brands (
    id SERIAL PRIMARY KEY, /* первичный ключ; автоинкремент, поэтому SERIAL */
    name VARCHAR(50) NOT NULL UNIQUE, /* состоит из одного слова, ограничиваем размер для экономии памяти */
    origin_country VARCHAR(50) NULL /* может состоять более чем из одного слова */
);

/* Создать таблицу car_models – модели */
CREATE TABLE car_shop.car_models (
    id SERIAL PRIMARY KEY, /* первичный ключ; автоинкремент, поэтому SERIAL */
    brand_id INTEGER NOT NULL REFERENCES car_shop.brands (id), /* внешний ключ, ссылка на бренд brands(id); модель всегда в рамках бренда, поэтому NOT NULL */
    name VARCHAR(50) NOT NULL, /* состоит из букв и цифр, ограничиваем размер */
    gasoline_consumption NUMERIC(3,1) NULL CHECK (gasoline_consumption > 0) /* может быть не целым числом, не может быть трехзначным; для электромобилей может быть NULL, для остальных положительная величина */
);

/* Создать таблицу colors – цвета */
CREATE TABLE car_shop.colors (
    id SERIAL PRIMARY KEY, /* первичный ключ; автоинкремент, поэтому SERIAL */
    name VARCHAR(50) NOT NULL /* слово, ограничиваем размер */
);

/* Создать таблицу customers – покупатели */
CREATE TABLE car_shop.customers (
    id SERIAL PRIMARY KEY, /* первичный ключ; автоинкремент, поэтому SERIAL */
    customer VARCHAR(50) NOT NULL, /* слово, ограничиваем размер */
    phone VARCHAR(50) NOT NULL UNIQUE, /* слово, ограничиваем размер; уникальный для каждого покупателя */
);

/* Создать таблицу sales_facts – продажи */
CREATE TABLE car_shop.sales_facts (
    id SERIAL PRIMARY KEY, /* первичный ключ; автоинкремент, поэтому SERIAL */
    car_model_id INTEGER NOT NULL REFERENCES car_shop.car_models (id), /* id модели – целое число, ссылка на таблицу моделей car_models */
    color_id INTEGER NOT NULL REFERENCES car_shop.colors (id), /* id цвета – целое число, ссылка на таблицу цветов colors */
    customer_id INTEGER NOT NULL REFERENCES car_shop.customers (id), /* id покупателя – целое число, связь с таблицей покупателей persons */
    date DATE NOT NULL, /* дата продажи без указания времени, тип DATE */
    price NUMERIC(9,2) NOT NULL CHECK (price > 0), /* цена не может быть больше семизначной суммы, два знака после запятой; должна быть положительной */
    discount INTEGER NOT NULL CHECK (discount >= 0 AND discount < 100) /* целое число от 0 до 100 не включая, скидка не может быть отрицательной и не может быть равна или больше 100% */
);

/* Заполнить данными таблицу brands */

INSERT INTO car_shop.brands (
    name,
    origin_country
) SELECT DISTINCT 
    TRIM(SPLIT_PART(s.auto, ' ', 1)), -- первое слово до пробела в колонке auto в сырых данных
    s.brand_origin
FROM raw_data.sales s;

/* Создаем временную вспомогательную таблицу raw_data.sales_prep, в которой далее разделим колонку auto на бренд, марку и цвет */
CREATE TABLE raw_data.sales_prep (
    id INTEGER,
    brand VARCHAR(50),
    model VARCHAR(50),
    color VARCHAR(50),
    gasoline_consumption NUMERIC(3,1),
    price NUMERIC(9,2),
    date DATE,
    person TEXT,
    phone TEXT,
    discount INTEGER,
    brand_origin TEXT
);

/* Заполняем таблицу raw_data.sales_prep, разделяем колонку auto на бренд, марку и цвет, остальное переносим без изменений */

INSERT INTO raw_data.sales_prep (id, brand, model, color, gasoline_consumption, price, date, person, phone, discount, brand_origin)
SELECT 
    id,
    SUBSTRING(auto, 1, STRPOS(auto, ' ') - 1), /* название бренда, первое слово до пробела */
    SUBSTRING(
        auto, 
        STRPOS(auto, ' ') + 1, 
        STRPOS(auto, ',') - STRPOS(auto, ' ') - 1), /* название модели, между первым пробелом и запятой */
    SUBSTRING(
        auto, 
        STRPOS(auto, ',') + 1, 
        LENGTH(auto) - STRPOS(auto, ',')), /* цвет, после запятой */
    gasoline_consumption,
    price,
    date,
    person,
    phone,
    discount,
    brand_origin
FROM raw_data.sales;

/* Переносим в таблицу car_models значения (модель и потребление топлива) из вспомогательной таблицы raw_data.sales_prep, соединяемся с ранее созданной и заполненной таблицей брендов car_shop.brands и оттуда берем id бренда */

INSERT INTO car_shop.car_models (brand_id, name, gasoline_consumption)
SELECT DISTINCT
    b.id AS brand_id,
    sp.model AS name,
    sp.gasoline_consumption
FROM raw_data.sales_prep sp 
INNER JOIN car_shop.brands b ON sp.brand = b.name;


/* Заполняем таблицу colors, перенося данные из временной вспомогательной таблицы raw_data.sales_prep */

INSERT INTO car_shop.colors ("name")
SELECT DISTINCT color 
FROM raw_data.sales_prep;

/* Заполняем таблицу customers, перенося данные из raw_data.sales */
INSERT INTO car_shop.customers (customer, phone)
SELECT DISTINCT
    person,
    phone
FROM raw_data.sales;


/* Заполняем данными таблицу car_shop.sales_facts, для этого соединяем вспомогательную таблицу raw_data.sales_prep с таблицами car_models, colors, customers, чтобы добыть id модели, цвета и покупателя */
INSERT INTO car_shop.sales_facts (car_model_id, color_id, customer_id, date, price, discount)
SELECT 
    cm.id,
    c.id,
    cc.id,
    sp.date,
    sp.price,
    sp.discount  
FROM raw_data.sales_prep sp 
LEFT JOIN car_shop.car_models cm ON sp.model = cm.name
LEFT JOIN car_shop.colors c ON sp.color = c.name
LEFT JOIN car_shop.customers cc ON sp.phone = cc.phone;


-- Этап 2. Создание выборок

---- Задание 1. Напишите запрос, который выведет процент моделей машин, у которых нет параметра `gasoline_consumption`.
/* счетчик строк с gasoline_consumption NULL, подсчет всех строк, вычисление процента */
SELECT 
    (SUM(CASE WHEN gasoline_consumption IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*))::NUMERIC(4,2) AS nulls_percentage_gasoline_consumption
FROM car_shop.car_models;

---- Задание 2. Напишите запрос, который покажет название бренда и среднюю цену его автомобилей в разбивке по всем годам с учётом скидки.
SELECT 
    b.name AS brand_name,
    EXTRACT(YEAR FROM sf.date) AS year, /* извлечь год из даты */
    ROUND(AVG(sf.price), 2) AS price_avg /* посчитать среднюю цену, округлить до двух знаков */
FROM car_shop.sales_facts sf
JOIN car_shop.car_models cm ON sf.car_model_id = cm.id /* соединить с таблицей моделей, чтобы добраться до брендов */
JOIN car_shop.brands b ON cm.brand_id = b.id /* дойти до таблицы брендов */
GROUP BY b.name, EXTRACT(YEAR FROM sf.date) /* сгруппировать по бренду и году */
ORDER BY b.name ASC, year ASC; /* отсортировать по бренду и году */


---- Задание 3. Посчитайте среднюю цену всех автомобилей с разбивкой по месяцам в 2022 году с учётом скидки.
SELECT 
    EXTRACT(MONTH FROM date) AS month, /* извлечь месяц из даты */
    2022 AS year, /* 2022 год укажем явно, ограничение по году дадим ниже в условии WHERE */
    ROUND(AVG(price), 2) AS price_avg /* рассчитать среднюю цену */
FROM car_shop.sales_facts
WHERE EXTRACT(YEAR FROM date) = 2022 /* только для 2022 года */
GROUP BY EXTRACT(MONTH FROM date) /* извлечь месяц из даты и сгруппировать по месяцам */
ORDER BY month ASC; /* отсортировать по месяцам */


---- Задание 4. Напишите запрос, который выведет список купленных машин у каждого пользователя.
SELECT 
    c.customer AS person,
    STRING_AGG(DISTINCT CONCAT(b.name, ' ', cm.name), ', ') AS cars /* соединить через пробел бренд и марку, исключить дубли, все соединить в строку через запятую и пробел */
FROM car_shop.customers c
JOIN car_shop.sales_facts sf ON c.id = sf.customer_id /* связь с таблицей покупателей, чтобы вытащить имя покупателя */
JOIN car_shop.car_models cm ON sf.car_model_id = cm.id /* связь с таблицей марок, чтобы добраться до таблицы брендов */
JOIN car_shop.brands b ON cm.brand_id = b.id
GROUP BY c.id /* группируем по покупателю */
ORDER BY c.customer ASC; /* сортируем по имени покупателя */



---- Задание 5. Напишите запрос, который покажет количество всех пользователей из США.
SELECT COUNT(*) AS persons_from_usa_count /* считаем строки… */
FROM car_shop.customers /* … в таблице покупателей */
WHERE phone LIKE '+1%'; /* только для покупателей, чьи телефоны начинаются с '+1' */




