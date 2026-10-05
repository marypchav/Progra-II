CREATE OR ALTER   PROCEDURE [dbo].[spCargarCatalogos]
AS
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"
    BEGIN TRY
        DECLARE @datos XML; -- variable que guardará el contenido completo del XML

        -- lee el archivo completo como binario (SINGLE_BLOB) y lo convierte a XML

        SELECT @datos = BulkColumn
        FROM OPENROWSET(BULK 'C:\Temp\catalogos.xml', SINGLE_BLOB) AS x;

        -- todas las cargas van en una transacción: si una falla, no queda nada a medias

        BEGIN TRANSACTION;

        -- tipos de documento de identidad

        INSERT INTO dbo.TipoDocuIdentidad (IdTipoDocuIdentidad, Nombre)
        SELECT Node.value('@Id', 'INT'), Node.value('@Nombre', 'VARCHAR(64)')
        FROM @datos.nodes('/Catalogos/Tipo_Doc/TipoDocuIdentidad') AS T(Node);

        -- tipos de moneda. El símbolo es NVARCHAR (Unicode) para que ₡ y € no se dañen

        INSERT INTO dbo.TipoMoneda (IdTipoMoneda, Nombre, Simbolo)
        SELECT Node.value('@Id', 'INT'), Node.value('@Nombre', 'VARCHAR(64)'),
               Node.value('@Simbolo', 'NVARCHAR(5)')
        FROM @datos.nodes('/Catalogos/Tipo_Moneda/TipoMoneda') AS T(Node);

        -- parentescos

        INSERT INTO dbo.Parentesco (IdParentesco, Nombre)
        SELECT Node.value('@Id', 'INT'), Node.value('@Nombre', 'VARCHAR(32)')
        FROM @datos.nodes('/Catalogos/Parentezcos/Parentezco') AS T(Node);

        -- tipos de cuenta de ahorro, se arreglan para que funcionen con las tablas

        INSERT INTO dbo.TipoCuentaAhorro (
            IdTipoCuentaAhorro, Nombre, IdTipoMoneda, SaldoMinimo, MultaSaldoMin,
            CargoMensualServicio, MaxOperHumanoGratis, MaxOperAutomaticoGratis,
            ComisionHumanoExceso, ComisionAutomaticoExceso, TasaInteresAnual)
        SELECT Node.value('@Id', 'INT')
             , Node.value('@Nombre', 'VARCHAR(50)')
             , Node.value('@IdTipoMoneda', 'INT') -- llave foránea a TipoMoneda
             , Node.value('@SaldoMinimo', 'MONEY')
             , Node.value('@MultaSaldoMin', 'MONEY')
             , Node.value('@CargoAnual', 'MONEY')
             , Node.value('@NumRetirosHumano', 'INT')
             , Node.value('@NumRetirosAutomatico', 'INT')
             , Node.value('@comisionHumano', 'MONEY')
             , Node.value('@comisionAutomatico', 'MONEY')
             , Node.value('@interes', 'DECIMAL(5,2)')
        FROM @datos.nodes('/Catalogos/Tipo_Cuenta_Ahorros/TipoCuentaAhorro') AS T(Node);

        -- tipos de operación de la bitácora (login, logout, agregar, etc.)

        INSERT INTO dbo.TipoOperacion (IdTipoOperacion, Nombre)
        SELECT Node.value('@id', 'INT'), Node.value('@nombre', 'VARCHAR(64)')
        FROM @datos.nodes('/Catalogos/TipoOperacionesBitacora/TipoOperacion') AS T(Node);

        -- se confirman los cambios
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        -- si algo falló se deshace todo y THROW vuelve a lanzar el error original para ver qué pasó
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO