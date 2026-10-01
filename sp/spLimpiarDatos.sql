CREATE OR ALTER PROCEDURE dbo.spLimpiarDatos
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM dbo.Bitacora;
        DELETE FROM dbo.UsuarioPuedeVer;
        DELETE FROM dbo.EstadoCuenta;
        DELETE FROM dbo.Beneficiario;
        DELETE FROM dbo.Cuenta;
        DELETE FROM dbo.Usuario;
        DELETE FROM dbo.Persona;

        DELETE FROM dbo.TipoCuentaAhorro;
        DELETE FROM dbo.TipoOperacion;
        DELETE FROM dbo.TipoMoneda;
        DELETE FROM dbo.Parentesco;
        DELETE FROM dbo.TipoDocuIdentidad;

        DBCC CHECKIDENT ('dbo.Bitacora',        RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('dbo.UsuarioPuedeVer', RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('dbo.EstadoCuenta',    RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('dbo.Beneficiario',    RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('dbo.Cuenta',          RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('dbo.Usuario',         RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('dbo.Persona',         RESEED, 0) WITH NO_INFOMSGS;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

EXEC dbo.LimpiarDatos;