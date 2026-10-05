CREATE OR ALTER   PROCEDURE [dbo].[spLimpiarDatos]
AS
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"
    BEGIN TRY

        -- todo en una transacción. se vacía todo, o no se toca nada

        BEGIN TRANSACTION;

        -- se borra en orden inverso a las llaves foráneas: primero las tablas que dependen de otras (hijas) y al final las que son referenciadas (padres)

        DELETE FROM dbo.Bitacora; -- depende de Usuario y TipoOperacion
        DELETE FROM dbo.UsuarioPuedeVer; -- depende de Usuario y Cuenta
        DELETE FROM dbo.EstadoCuenta; -- depende de Cuenta
        DELETE FROM dbo.Beneficiario; -- depende de Cuenta, Persona y Parentesco
        DELETE FROM dbo.Cuenta; -- depende de Persona y TipoCuentaAhorro
        DELETE FROM dbo.Usuario; -- depende de Persona
        DELETE FROM dbo.Persona; -- depende de TipoDocuIdentidad

        -- luego los catálogos, también de hijas a padres (TipoCuentaAhorro depende de TipoMoneda)

        DELETE FROM dbo.TipoCuentaAhorro;
        DELETE FROM dbo.TipoOperacion;
        DELETE FROM dbo.TipoMoneda;
        DELETE FROM dbo.Parentesco;
        DELETE FROM dbo.TipoDocuIdentidad;

        -- reinicia los contadores identity de las tablas no-catálogo para que los ids vuelvan a empezar
        -- los catálogos no se reinician porque no son identity

        DBCC CHECKIDENT ('dbo.Bitacora',        RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('dbo.UsuarioPuedeVer', RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('dbo.EstadoCuenta',    RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('dbo.Beneficiario',    RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('dbo.Cuenta',          RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('dbo.Usuario',         RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('dbo.Persona',         RESEED, 0) WITH NO_INFOMSGS;

        -- se confirman los cambios

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH

        -- si algo falla se deshace todo y THROW vuelve a lanzar el error original

        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO