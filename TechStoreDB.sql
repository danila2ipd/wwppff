-- ============================================================
--  TechStoreDB — Скрипт базы данных для SQL Server (SSMS)
--  Запускать: открыть в SSMS → Execute (F5)
-- ============================================================

USE master;
GO

-- Пересоздать БД (закомментируйте IF EXISTS если хотите сохранить данные)
IF EXISTS (SELECT name FROM sys.databases WHERE name = N'TechStoreDB')
BEGIN
    ALTER DATABASE TechStoreDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE TechStoreDB;
END
GO

CREATE DATABASE TechStoreDB
    COLLATE Cyrillic_General_CI_AS;
GO

USE TechStoreDB;
GO

-- ============================================================
--  ТАБЛИЦЫ
-- ============================================================

-- ------------------------------------------------------------
--  Типы пользователей (роли)
-- ------------------------------------------------------------
CREATE TABLE Roles (
    Id   INT          NOT NULL IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(50) NOT NULL UNIQUE
);
GO

INSERT INTO Roles (Name) VALUES ('Admin'), ('Manager');
GO

-- ------------------------------------------------------------
--  Пользователи
-- ------------------------------------------------------------
CREATE TABLE Users (
    Id           INT            NOT NULL IDENTITY(1,1) PRIMARY KEY,
    Login        NVARCHAR(100)  NOT NULL,
    PasswordHash NVARCHAR(255)  NOT NULL,
    FullName     NVARCHAR(200)  NOT NULL DEFAULT '',
    Email        NVARCHAR(200)  NOT NULL DEFAULT '',
    RoleId       INT            NOT NULL DEFAULT 2,  -- Manager
    IsActive     BIT            NOT NULL DEFAULT 1,
    CreatedAt    DATETIME2      NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT UQ_Users_Login FOREIGN KEY (RoleId) REFERENCES Roles(Id),
    CONSTRAINT UQ_Login       UNIQUE (Login)
);
GO

-- Индекс на логин
CREATE UNIQUE INDEX IX_Users_Login ON Users (Login);
GO

-- ------------------------------------------------------------
--  Категории товаров
-- ------------------------------------------------------------
CREATE TABLE Categories (
    Id          INT            NOT NULL IDENTITY(1,1) PRIMARY KEY,
    Name        NVARCHAR(150)  NOT NULL,
    Description NVARCHAR(500)  NOT NULL DEFAULT '',
    SortOrder   INT            NOT NULL DEFAULT 0,
    IsActive    BIT            NOT NULL DEFAULT 1
);
GO

CREATE INDEX IX_Categories_Sort ON Categories (SortOrder, Name);
GO

-- ------------------------------------------------------------
--  Товары
-- ------------------------------------------------------------
CREATE TABLE Products (
    Id          INT             NOT NULL IDENTITY(1,1) PRIMARY KEY,
    CategoryId  INT             NOT NULL,
    Name        NVARCHAR(255)   NOT NULL,
    Description NVARCHAR(2000)  NOT NULL DEFAULT '',
    Sku         NVARCHAR(100)   NOT NULL DEFAULT '',
    Price       DECIMAL(18,2)   NOT NULL DEFAULT 0,
    Stock       INT             NOT NULL DEFAULT 0,
    ImagePath   NVARCHAR(500)   NOT NULL DEFAULT '',
    IsActive    BIT             NOT NULL DEFAULT 1,
    CreatedAt   DATETIME2       NOT NULL DEFAULT GETUTCDATE(),

    CONSTRAINT FK_Products_Category FOREIGN KEY (CategoryId)
        REFERENCES Categories(Id),
    CONSTRAINT CK_Products_Price    CHECK (Price >= 0),
    CONSTRAINT CK_Products_Stock    CHECK (Stock >= 0)
);
GO

CREATE INDEX IX_Products_Category ON Products (CategoryId);
CREATE INDEX IX_Products_Sku       ON Products (Sku);
CREATE INDEX IX_Products_Active    ON Products (IsActive, CategoryId);
GO

-- ------------------------------------------------------------
--  Заказы
-- ------------------------------------------------------------
CREATE TABLE Orders (
    Id          INT             NOT NULL IDENTITY(1,1) PRIMARY KEY,
    UserId      INT             NULL,                       -- NULL если гость
    ClientName  NVARCHAR(200)   NOT NULL,
    ClientPhone NVARCHAR(30)    NOT NULL DEFAULT '',
    ClientEmail NVARCHAR(200)   NOT NULL DEFAULT '',
    Address     NVARCHAR(500)   NOT NULL DEFAULT '',
    Comment     NVARCHAR(1000)  NOT NULL DEFAULT '',
    Status      TINYINT         NOT NULL DEFAULT 0,
        -- 0=Новый 1=В обработке 2=Отправлен 3=Доставлен 4=Отменён
    CreatedAt   DATETIME2       NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt   DATETIME2       NULL,

    CONSTRAINT FK_Orders_User FOREIGN KEY (UserId)
        REFERENCES Users(Id) ON DELETE SET NULL,
    CONSTRAINT CK_Orders_Status CHECK (Status BETWEEN 0 AND 4)
);
GO

CREATE INDEX IX_Orders_Status    ON Orders (Status);
CREATE INDEX IX_Orders_CreatedAt ON Orders (CreatedAt DESC);
CREATE INDEX IX_Orders_User      ON Orders (UserId);
GO

-- ------------------------------------------------------------
--  Позиции заказа
-- ------------------------------------------------------------
CREATE TABLE OrderItems (
    Id         INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    OrderId    INT           NOT NULL,
    ProductId  INT           NOT NULL,
    Quantity   INT           NOT NULL,
    UnitPrice  DECIMAL(18,2) NOT NULL,  -- цена зафиксирована на момент заказа

    CONSTRAINT FK_OrderItems_Order   FOREIGN KEY (OrderId)
        REFERENCES Orders(Id) ON DELETE CASCADE,
    CONSTRAINT FK_OrderItems_Product FOREIGN KEY (ProductId)
        REFERENCES Products(Id),
    CONSTRAINT CK_OrderItems_Qty     CHECK (Quantity > 0),
    CONSTRAINT CK_OrderItems_Price   CHECK (UnitPrice >= 0)
);
GO

CREATE INDEX IX_OrderItems_Order   ON OrderItems (OrderId);
CREATE INDEX IX_OrderItems_Product ON OrderItems (ProductId);
GO

-- ============================================================
--  ПРЕДСТАВЛЕНИЯ
-- ============================================================

-- Заказы с итоговой суммой
CREATE OR ALTER VIEW vw_Orders AS
    SELECT
        o.Id,
        o.UserId,
        o.ClientName,
        o.ClientPhone,
        o.ClientEmail,
        o.Address,
        o.Comment,
        o.Status,
        CASE o.Status
            WHEN 0 THEN N'Новый'
            WHEN 1 THEN N'В обработке'
            WHEN 2 THEN N'Отправлен'
            WHEN 3 THEN N'Доставлен'
            WHEN 4 THEN N'Отменён'
        END                                    AS StatusLabel,
        o.CreatedAt,
        o.UpdatedAt,
        ISNULL(SUM(i.Quantity * i.UnitPrice), 0) AS Total,
        ISNULL(SUM(i.Quantity), 0)               AS ItemCount
    FROM Orders o
    LEFT JOIN OrderItems i ON i.OrderId = o.Id
    GROUP BY
        o.Id, o.UserId, o.ClientName, o.ClientPhone,
        o.ClientEmail, o.Address, o.Comment,
        o.Status, o.CreatedAt, o.UpdatedAt;
GO

-- Товары с категорией
CREATE OR ALTER VIEW vw_Products AS
    SELECT
        p.Id,
        p.CategoryId,
        c.Name  AS CategoryName,
        p.Name,
        p.Description,
        p.Sku,
        p.Price,
        p.Stock,
        p.ImagePath,
        p.IsActive,
        p.CreatedAt,
        CASE
            WHEN p.Stock  = 0 THEN N'Нет в наличии'
            WHEN p.Stock <= 5 THEN N'Мало (' + CAST(p.Stock AS NVARCHAR) + N' шт.)'
            ELSE N'В наличии (' + CAST(p.Stock AS NVARCHAR) + N' шт.)'
        END AS StockStatus
    FROM Products p
    JOIN Categories c ON c.Id = p.CategoryId;
GO

-- Статистика по категориям
CREATE OR ALTER VIEW vw_CategoryStats AS
    SELECT
        c.Id,
        c.Name,
        COUNT(p.Id)                    AS ProductCount,
        SUM(CASE WHEN p.Stock = 0 AND p.IsActive = 1 THEN 1 ELSE 0 END) AS OutOfStock,
        SUM(CASE WHEN p.IsActive = 1 THEN 1 ELSE 0 END) AS ActiveCount
    FROM Categories c
    LEFT JOIN Products p ON p.CategoryId = c.Id
    GROUP BY c.Id, c.Name;
GO

-- ============================================================
--  ХРАНИМЫЕ ПРОЦЕДУРЫ
-- ============================================================

-- Дашборд — одним запросом
CREATE OR ALTER PROCEDURE sp_GetDashboardStats
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        (SELECT COUNT(*)     FROM Orders)                    AS TotalOrders,
        (SELECT COUNT(*)     FROM Orders WHERE Status = 0)   AS NewOrders,
        (SELECT ISNULL(SUM(i.Quantity * i.UnitPrice), 0)
         FROM OrderItems i
         JOIN Orders o ON o.Id = i.OrderId
         WHERE o.Status <> 4)                                AS TotalRevenue,
        (SELECT COUNT(*)     FROM Products WHERE IsActive=1) AS ActiveProducts,
        (SELECT COUNT(*)     FROM Products
         WHERE IsActive=1 AND Stock=0)                       AS OutOfStockProducts,
        (SELECT COUNT(*)     FROM Categories WHERE IsActive=1) AS ActiveCategories,
        (SELECT COUNT(*)     FROM Users WHERE IsActive=1)    AS ActiveUsers;
END;
GO

-- Поиск товаров
CREATE OR ALTER PROCEDURE sp_SearchProducts
    @Query      NVARCHAR(200) = NULL,
    @CategoryId INT           = NULL,
    @ShowAll    BIT           = 0       -- 1 = включая неактивные
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM   vw_Products
    WHERE  (@ShowAll = 1 OR IsActive = 1)
      AND  (@CategoryId IS NULL OR CategoryId = @CategoryId)
      AND  (@Query IS NULL
            OR Name        LIKE '%' + @Query + '%'
            OR Sku         LIKE '%' + @Query + '%'
            OR Description LIKE '%' + @Query + '%')
    ORDER BY CategoryName, Name;
END;
GO

-- Создание заказа (транзакция: проверка остатков + списание)
CREATE OR ALTER PROCEDURE sp_CreateOrder
    @ClientName  NVARCHAR(200),
    @ClientPhone NVARCHAR(30),
    @ClientEmail NVARCHAR(200),
    @Address     NVARCHAR(500),
    @Comment     NVARCHAR(1000),
    @UserId      INT = NULL,
    -- Позиции передаются как XML:
    -- <items><item productId="1" quantity="2"/></items>
    @ItemsXml    XML,
    @NewOrderId  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Разбираем XML позиций
        CREATE TABLE #Items (
            ProductId INT NOT NULL,
            Quantity  INT NOT NULL
        );

        INSERT INTO #Items (ProductId, Quantity)
        SELECT
            item.value('@productId', 'INT'),
            item.value('@quantity',  'INT')
        FROM @ItemsXml.nodes('/items/item') AS T(item);

        -- Проверяем остатки
        DECLARE @Bad NVARCHAR(400);
        SELECT TOP 1 @Bad = p.Name + N' (запрошено ' +
               CAST(i.Quantity AS NVARCHAR) + N', в наличии ' +
               CAST(p.Stock AS NVARCHAR) + N')'
        FROM   #Items i
        JOIN   Products p ON p.Id = i.ProductId
        WHERE  p.Stock < i.Quantity;

        IF @Bad IS NOT NULL
            THROW 50001, @Bad, 1;

        -- Создаём заказ
        INSERT INTO Orders (ClientName, ClientPhone, ClientEmail,
                            Address, Comment, UserId)
        VALUES (@ClientName, @ClientPhone, @ClientEmail,
                @Address, @Comment, @UserId);

        SET @NewOrderId = SCOPE_IDENTITY();

        -- Добавляем позиции (цена фиксируется)
        INSERT INTO OrderItems (OrderId, ProductId, Quantity, UnitPrice)
        SELECT @NewOrderId, i.ProductId, i.Quantity, p.Price
        FROM   #Items i
        JOIN   Products p ON p.Id = i.ProductId;

        -- Списываем остатки
        UPDATE p
        SET    p.Stock = p.Stock - i.Quantity
        FROM   Products p
        JOIN   #Items i ON i.ProductId = p.Id;

        DROP TABLE #Items;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DROP TABLE IF EXISTS #Items;
        THROW;
    END CATCH
END;
GO

-- Смена статуса заказа
CREATE OR ALTER PROCEDURE sp_UpdateOrderStatus
    @OrderId INT,
    @Status  TINYINT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Orders
    SET    Status    = @Status,
           UpdatedAt = GETUTCDATE()
    WHERE  Id = @OrderId;
END;
GO

-- Выручка по месяцам (для графика)
CREATE OR ALTER PROCEDURE sp_GetMonthlyRevenue
    @Months INT = 6
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        FORMAT(o.CreatedAt, 'MM.yyyy')       AS Month,
        SUM(i.Quantity * i.UnitPrice)        AS Revenue,
        COUNT(DISTINCT o.Id)                 AS OrderCount
    FROM  Orders o
    JOIN  OrderItems i ON i.OrderId = o.Id
    WHERE o.Status   <> 4
      AND o.CreatedAt >= DATEADD(MONTH, -@Months + 1,
                          DATEFROMPARTS(YEAR(GETUTCDATE()),
                                        MONTH(GETUTCDATE()), 1))
    GROUP BY FORMAT(o.CreatedAt, 'MM.yyyy'),
             YEAR(o.CreatedAt), MONTH(o.CreatedAt)
    ORDER BY YEAR(o.CreatedAt), MONTH(o.CreatedAt);
END;
GO

-- ============================================================
--  НАЧАЛЬНЫЕ ДАННЫЕ
-- ============================================================

-- Администратор (пароль: admin123 — BCrypt hash)
-- Чтобы изменить пароль — запустите приложение и поменяйте через панель
INSERT INTO Users (Login, PasswordHash, FullName, Email, RoleId, IsActive)
VALUES (
    'admin',
    '$2a$11$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy',
    N'Администратор',
    'admin@store.local',
    1,  -- Admin
    1
);
GO

-- Категории
INSERT INTO Categories (Name, SortOrder) VALUES
    (N'Смартфоны',       0),
    (N'Ноутбуки',        1),
    (N'Планшеты',        2),
    (N'Телевизоры',      3),
    (N'Аудиотехника',    4),
    (N'Аксессуары',      5),
    (N'Умный дом',       6),
    (N'Игровые консоли', 7);
GO

-- Товары
INSERT INTO Products (CategoryId, Name, Sku, Price, Stock, Description)
SELECT c.Id, v.Name, v.Sku, v.Price, v.Stock, v.Descr
FROM (VALUES
    (N'Смартфоны', N'iPhone 15 Pro 256GB',         N'APL-IP15P-256',   109990, 12,
     N'Смартфон Apple с чипом A17 Pro, камерой 48 МП и титановым корпусом.'),
    (N'Смартфоны', N'Samsung Galaxy S24 Ultra',     N'SAM-S24U-512',    124990,  8,
     N'Флагман Samsung с S Pen, 200 МП камерой и Snapdragon 8 Gen 3.'),
    (N'Смартфоны', N'Xiaomi Redmi Note 13 Pro',     N'XMI-RN13P-256',   29990, 25,
     N'Смартфон с AMOLED 120 Гц и 200 МП камерой.'),
    (N'Ноутбуки',  N'MacBook Pro 14" M3',           N'APL-MBP14-M3',   199990,  5,
     N'Ноутбук Apple с чипом M3 и дисплеем Liquid Retina XDR.'),
    (N'Ноутбуки',  N'ASUS ROG Zephyrus G14',        N'ASU-ROG-G14',    134990,  7,
     N'Игровой ноутбук AMD Ryzen 9, RTX 4060, 14" OLED.'),
    (N'Ноутбуки',  N'Lenovo IdeaPad 3 Gen 8',       N'LEN-IP3-G8',      49990,  3,
     N'Ноутбук Intel Core i5, 15.6" FHD IPS.'),
    (N'Планшеты',  N'iPad Pro 12.9" M2',            N'APL-IPAD-P12-M2',119990,  9,
     N'Планшет Apple с чипом M2 и Mini-LED.'),
    (N'Планшеты',  N'Samsung Galaxy Tab S9+',       N'SAM-TABS9P',      89990,  6,
     N'AMOLED 12.4", Snapdragon 8 Gen 2.'),
    (N'Телевизоры',N'LG OLED C3 55"',              N'LG-OLEDC3-55',    139990,  4,
     N'OLED 4K 120 Гц, Dolby Vision, webOS.'),
    (N'Телевизоры',N'Sony Bravia XR 65"',           N'SON-XR65-A95L',  249990,  2,
     N'QD-OLED, процессор Cognitive XR.'),
    (N'Аудиотехника',N'Sony WH-1000XM5',            N'SON-WH1000XM5',   29990, 18,
     N'Наушники с лучшим шумоподавлением в классе.'),
    (N'Аудиотехника',N'AirPods Pro 2',              N'APL-APP2',         24990, 20,
     N'Беспроводные наушники с ANC и чипом H2.'),
    (N'Аксессуары',  N'Apple Watch Series 9 45mm',  N'APL-AWS9-45',      44990, 11,
     N'Смарт-часы S9, Always-On, Double Tap.'),
    (N'Аксессуары',  N'Чехол iPhone 15 Pro (кожа)', N'ACC-CASE-IP15P',   3990, 50,
     N'Оригинальный кожаный чехол.'),
    (N'Умный дом',   N'Xiaomi Smart Plug',           N'XMI-SMPLUG',        990,  0,
     N'Умная розетка с управлением через приложение.'),
    (N'Игровые консоли',N'Sony PlayStation 5 Slim',  N'SON-PS5-SLIM',    49990,  2,
     N'Консоль Sony SSD 1 ТБ, 4K, 120 FPS.')
) AS v(Cat, Name, Sku, Price, Stock, Descr)
JOIN Categories c ON c.Name = v.Cat;
GO

-- Тестовые заказы
DECLARE @O1 INT, @O2 INT, @O3 INT;

INSERT INTO Orders (ClientName, ClientPhone, ClientEmail, Address, Status)
VALUES (N'Иванов Иван', '+7(495)111-11-11', 'ivan@mail.ru',
        N'Москва, ул. Ленина, 1', 3);     -- Доставлен
SET @O1 = SCOPE_IDENTITY();

INSERT INTO Orders (ClientName, ClientPhone, ClientEmail, Address, Status)
VALUES (N'Петрова Анна', '+7(812)222-22-22', 'anna@mail.ru',
        N'СПб, пр. Невский, 10', 1);      -- В обработке
SET @O2 = SCOPE_IDENTITY();

INSERT INTO Orders (ClientName, ClientPhone, ClientEmail, Address, Status)
VALUES (N'Сидоров Пётр', '+7(843)333-33-33', 'petr@mail.ru',
        N'Казань, ул. Баумана, 5', 0);    -- Новый
SET @O3 = SCOPE_IDENTITY();

INSERT INTO OrderItems (OrderId, ProductId, Quantity, UnitPrice)
SELECT @O1, Id, 1, Price FROM Products WHERE Sku = 'APL-IP15P-256' UNION ALL
SELECT @O1, Id, 1, Price FROM Products WHERE Sku = 'APL-APP2'      UNION ALL
SELECT @O2, Id, 1, Price FROM Products WHERE Sku = 'APL-MBP14-M3'  UNION ALL
SELECT @O3, Id, 2, Price FROM Products WHERE Sku = 'SON-WH1000XM5' UNION ALL
SELECT @O3, Id, 1, Price FROM Products WHERE Sku = 'APL-AWS9-45';
GO

-- ============================================================
--  ПРОВЕРКА
-- ============================================================
PRINT '=== Итого в БД ==='
SELECT 'Users'      AS [Таблица], COUNT(*) AS [Строк] FROM Users      UNION ALL
SELECT 'Categories',               COUNT(*)            FROM Categories  UNION ALL
SELECT 'Products',                 COUNT(*)            FROM Products    UNION ALL
SELECT 'Orders',                   COUNT(*)            FROM Orders      UNION ALL
SELECT 'OrderItems',               COUNT(*)            FROM OrderItems;

PRINT '=== Статистика (sp_GetDashboardStats) ==='
EXEC sp_GetDashboardStats;

PRINT '=== Поиск "Apple" ==='
EXEC sp_SearchProducts @Query = N'Apple';

PRINT 'База TechStoreDB создана и готова к работе!'
GO
