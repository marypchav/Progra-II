CREATE OR ALTER PROCEDURE dbo.spCargarCatalogos
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @datos XML;

        SELECT @datos = BulkColumn
        FROM OPENROWSET(BULK 'C:\Temp\catalogos.xml', SINGLE_BLOB) AS x;

        BEGIN TRANSACTION;

        INSERT INTO dbo.TipoDocuIdentidad (IdTipoDocuIdentidad, Nombre)
        SELECT Node.value('@Id', 'INT'), Node.value('@Nombre', 'VARCHAR(64)')
        FROM @datos.nodes('/Catalogos/Tipo_Doc/TipoDocuIdentidad') AS T(Node);

        INSERT INTO dbo.TipoMoneda (IdTipoMoneda, Nombre, Simbolo)
        SELECT Node.value('@Id', 'INT'), Node.value('@Nombre', 'VARCHAR(64)'),
               Node.value('@Simbolo', 'NVARCHAR(5)')
        FROM @datos.nodes('/Catalogos/Tipo_Moneda/TipoMoneda') AS T(Node);

        INSERT INTO dbo.Parentesco (IdParentesco, Nombre)
        SELECT Node.value('@Id', 'INT'), Node.value('@Nombre', 'VARCHAR(32)')
        FROM @datos.nodes('/Catalogos/Parentezcos/Parentezco') AS T(Node);

        INSERT INTO dbo.TipoCuentaAhorro (
            IdTipoCuentaAhorro, Nombre, IdTipoMoneda, SaldoMinimo, MultaSaldoMin,
            CargoMensualServicio, MaxOperHumanoGratis, MaxOperAutomaticoGratis,
            ComisionHumanoExceso, ComisionAutomaticoExceso, TasaInteresAnual)
        SELECT Node.value('@Id', 'INT')
             , Node.value('@Nombre', 'VARCHAR(50)')
             , Node.value('@IdTipoMoneda', 'INT')
             , Node.value('@SaldoMinimo', 'MONEY')
             , Node.value('@MultaSaldoMin', 'MONEY')
             , Node.value('@CargoAnual', 'MONEY')
             , Node.value('@NumRetirosHumano', 'INT')
             , Node.value('@NumRetirosAutomatico', 'INT')
             , Node.value('@comisionHumano', 'MONEY')
             , Node.value('@comisionAutomatico', 'MONEY')
             , Node.value('@interes', 'DECIMAL(5,2)')
        FROM @datos.nodes('/Catalogos/Tipo_Cuenta_Ahorros/TipoCuentaAhorro') AS T(Node);

        INSERT INTO dbo.TipoOperacion (IdTipoOperacion, Nombre)
        SELECT Node.value('@id', 'INT'), Node.value('@nombre', 'VARCHAR(64)')
        FROM @datos.nodes('/Catalogos/TipoOperacionesBitacora/TipoOperacion') AS T(Node);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

EXEC dbo.CargarCatalogos;