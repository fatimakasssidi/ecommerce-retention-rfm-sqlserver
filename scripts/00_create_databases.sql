/*
Purpose : Create the two project databases and their schemas.
          ecommerce_rfm_raw : raw landing data (bronze) and load logs
          ecommerce_rfm_dwh : clean data (silver, gold), logs and serving views
Task    : E0-07
Layer   : setup
Re-run  : safe, nothing is dropped and existing objects are skipped
*/

USE master;
GO

/* ---------------------------------------------------------------
   1. Databases
   --------------------------------------------------------------- */
IF DB_ID(N'ecommerce_rfm_raw') IS NULL
    CREATE DATABASE ecommerce_rfm_raw;
GO

IF DB_ID(N'ecommerce_rfm_dwh') IS NULL
    CREATE DATABASE ecommerce_rfm_dwh;
GO

/* ---------------------------------------------------------------
   2. Recovery model
   raw : SIMPLE, because it can be rebuilt from the source files and
         this keeps the log small during huge bulk loads.
   dwh : FULL, the real asset. Until the first full backup is taken
         (task E9), SQL Server truncates its log like SIMPLE does.
   --------------------------------------------------------------- */
ALTER DATABASE ecommerce_rfm_raw SET RECOVERY SIMPLE;
ALTER DATABASE ecommerce_rfm_dwh SET RECOVERY FULL;
GO

/* ---------------------------------------------------------------
   3. File growth
   Fixed growth steps avoid many tiny autogrowths during big loads.
   Only the growth is set (not the size), so this stays re-runnable.
   --------------------------------------------------------------- */
ALTER DATABASE ecommerce_rfm_raw MODIFY FILE (NAME = N'ecommerce_rfm_raw',     FILEGROWTH = 512MB);
ALTER DATABASE ecommerce_rfm_raw MODIFY FILE (NAME = N'ecommerce_rfm_raw_log', FILEGROWTH = 256MB);
ALTER DATABASE ecommerce_rfm_dwh MODIFY FILE (NAME = N'ecommerce_rfm_dwh',     FILEGROWTH = 512MB);
ALTER DATABASE ecommerce_rfm_dwh MODIFY FILE (NAME = N'ecommerce_rfm_dwh_log', FILEGROWTH = 256MB);
GO

/* ---------------------------------------------------------------
   4. Schemas: ecommerce_rfm_raw
   --------------------------------------------------------------- */
USE ecommerce_rfm_raw;
GO

IF SCHEMA_ID(N'bronze') IS NULL EXEC(N'CREATE SCHEMA bronze AUTHORIZATION dbo;');
IF SCHEMA_ID(N'audit')  IS NULL EXEC(N'CREATE SCHEMA audit  AUTHORIZATION dbo;');
GO

/* ---------------------------------------------------------------
   5. Schemas: ecommerce_rfm_dwh
   --------------------------------------------------------------- */
USE ecommerce_rfm_dwh;
GO

IF SCHEMA_ID(N'silver')  IS NULL EXEC(N'CREATE SCHEMA silver  AUTHORIZATION dbo;');
IF SCHEMA_ID(N'gold')    IS NULL EXEC(N'CREATE SCHEMA gold    AUTHORIZATION dbo;');
IF SCHEMA_ID(N'audit')   IS NULL EXEC(N'CREATE SCHEMA audit   AUTHORIZATION dbo;');
IF SCHEMA_ID(N'serving') IS NULL EXEC(N'CREATE SCHEMA serving AUTHORIZATION dbo;');
GO
