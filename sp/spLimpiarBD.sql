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

    EXEC dbo.spCargarEntidad
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
            DELETE FROM dbo.Bitacora; -- depende de Usuario y TipoOperacion
            DELETE FROM dbo.UsuarioPuedeVer; -- depende de Usuario y Cuenta
            DELETE FROM dbo.EstadoCuenta; -- depende de Cuenta
            DELETE FROM dbo.Beneficiario; -- depende de Cuenta, Persona y Parentesco
            DELETE FROM dbo.Cuenta; -- depende de Persona y TipoCuentaAhorro
            DELETE FROM dbo.Usuario; -- depende de Persona
            DELETE FROM dbo.Persona; -- depende de TipoDocuIdentidad

            -- catálogos, también de hijas a padres
            DELETE FROM dbo.TipoCuentaAhorro;   -- depende de TipoMoneda
            DELETE FROM dbo.TipoOperacion;
            DELETE FROM dbo.TipoMoneda;
            DELETE FROM dbo.Parentesco;
            DELETE FROM dbo.TipoDocuIdentidad;

            -- reinicia los IDENTITY de las tablas no-catálogo para que los ids
            -- vuelvan a empezar en 1 (los catálogos no son IDENTITY)
            DBCC CHECKIDENT ('dbo.Bitacora', RESEED, 0) WITH NO_INFOMSGS;
            DBCC CHECKIDENT ('dbo.UsuarioPuedeVer', RESEED, 0) WITH NO_INFOMSGS;
            DBCC CHECKIDENT ('dbo.EstadoCuenta', RESEED, 0) WITH NO_INFOMSGS;
            DBCC CHECKIDENT ('dbo.Beneficiario', RESEED, 0) WITH NO_INFOMSGS;
            DBCC CHECKIDENT ('dbo.Cuenta', RESEED, 0) WITH NO_INFOMSGS;
            DBCC CHECKIDENT ('dbo.Usuario', RESEED, 0) WITH NO_INFOMSGS;
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
