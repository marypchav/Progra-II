CREATE OR ALTER PROCEDURE dbo.spLimpiarBD
    @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución (recarga completa):
    DECLARE @resultado INT;

    EXEC dbo.spLimpiarBD
        @outResultCode = @resultado OUTPUT;

    EXEC dbo.spCargarCatalogo
        @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- transacción: se vacía todo o no se toca nada
        BEGIN TRANSACTION tLimpiarBD;

            -- se borra en orden inverso a las llaves foráneas:
            -- primero las tablas hijas y al final las referenciadas (padres)
            DELETE FROM dbo.Comprobante; -- depende de Movimiento
            DELETE FROM dbo.Movimiento; -- depende de Cuenta, EstadoCuenta, TipoMovimiento y OperacionXML
            DELETE FROM dbo.ControlSimulacion;
            DELETE FROM dbo.OperacionXML;
            DELETE FROM dbo.Bitacora; -- depende de Usuario y TipoOperacion
            DELETE FROM dbo.UsuarioPuedeVer; -- depende de Usuario y Cuenta
            DELETE FROM dbo.EstadoCuenta; -- depende de Cuenta
            DELETE FROM dbo.Beneficiario; -- depende de Cuenta, Persona y Parentesco
            DELETE FROM dbo.Cuenta; -- depende de Persona y TipoCuentaAhorro
            DELETE FROM dbo.Usuario; -- depende de Persona
            DELETE FROM dbo.Persona; -- depende de TipoDocuIdentidad

            -- catálogos, también de hijas a padres
            DELETE FROM dbo.TipoCuentaAhorro; -- depende de TipoMoneda
            DELETE FROM dbo.TipoMovimiento;
            DELETE FROM dbo.TipoOperacion;
            DELETE FROM dbo.TipoMoneda;
            DELETE FROM dbo.Parentesco;
            DELETE FROM dbo.TipoDocuIdentidad;

            -- reinicia los IDENTITY para que los ids vuelvan a empezar en 1.
            -- solo se reinician las tablas que ya tuvieron filas: en una tabla
            -- recién creada, RESEED 0 haría que el primer id fuera 0
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.Comprobante')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.Comprobante', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.Movimiento')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.Movimiento', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.ControlSimulacion')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.ControlSimulacion', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.OperacionXML')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.OperacionXML', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.Bitacora')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.Bitacora', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.UsuarioPuedeVer')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.UsuarioPuedeVer', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.EstadoCuenta')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.EstadoCuenta', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.Beneficiario')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.Beneficiario', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.Cuenta')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.Cuenta', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.Usuario')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.Usuario', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.Persona')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.Persona', RESEED, 0) WITH NO_INFOMSGS;

        COMMIT TRANSACTION tLimpiarBD;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO