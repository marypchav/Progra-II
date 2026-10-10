CREATE OR ALTER PROCEDURE dbo.spCargarCatalogo
    @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spCargarCatalogo
        @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- variables de uso general
        DECLARE @datos XML; -- contenido completo del XML

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- preprocesamiento: lee el archivo como binario (SINGLE_BLOB) y lo
        -- convierte a XML, respetando el UTF-8 declarado (para ₡ y €)
        SELECT @datos = X.BulkColumn
        FROM OPENROWSET(BULK 'C:\Temp\catalogos.xml', SINGLE_BLOB) AS X;

        -- transacción: si una carga falla, no queda nada a medias
        BEGIN TRANSACTION tCargarCatalogo;

            -- tipos de documento de identidad
            INSERT INTO dbo.TipoDocuIdentidad (
                IdTipoDocuIdentidad
                , Nombre
            )
            SELECT T.Nodo.value('@Id', 'INT')
                , T.Nodo.value('@Nombre', 'VARCHAR(64)')
            FROM @datos.nodes('/Catalogos/Tipo_Doc/TipoDocuIdentidad') AS T(Nodo);

            -- tipos de moneda. el símbolo es NVARCHAR para que ₡ y € no se dañen
            INSERT INTO dbo.TipoMoneda (
                IdTipoMoneda
                , Nombre
                , Simbolo
            )
            SELECT T.Nodo.value('@Id', 'INT')
                , T.Nodo.value('@Nombre', 'VARCHAR(64)')
                , T.Nodo.value('@Simbolo', 'NVARCHAR(5)')
            FROM @datos.nodes('/Catalogos/Tipo_Moneda/TipoMoneda') AS T(Nodo);

            -- parentescos (el XML los escribe "Parentezco")
            INSERT INTO dbo.Parentesco (
                IdParentesco
                , Nombre
            )
            SELECT T.Nodo.value('@Id', 'INT')
                , T.Nodo.value('@Nombre', 'VARCHAR(32)')
            FROM @datos.nodes('/Catalogos/Parentezcos/Parentezco') AS T(Nodo);

            -- tipos de cuenta de ahorro: los atributos del XML se mapean a las
            -- columnas de la tabla
            INSERT INTO dbo.TipoCuentaAhorro (
                IdTipoCuentaAhorro
                , Nombre
                , IdTipoMoneda
                , SaldoMinimo
                , MultaSaldoMin
                , CargoMensualServicio
                , MaxOperHumanoGratis
                , MaxOperAutomaticoGratis
                , ComisionHumanoExceso
                , ComisionAutomaticoExceso
                , TasaInteresAnual
            )
            SELECT T.Nodo.value('@Id', 'INT')
                , T.Nodo.value('@Nombre', 'VARCHAR(50)')
                , T.Nodo.value('@IdTipoMoneda', 'INT')
                , T.Nodo.value('@SaldoMinimo', 'MONEY')
                , T.Nodo.value('@MultaSaldoMin', 'MONEY')
                , T.Nodo.value('@CargoAnual', 'MONEY')
                , T.Nodo.value('@NumRetirosHumano', 'INT')
                , T.Nodo.value('@NumRetirosAutomatico', 'INT')
                , T.Nodo.value('@comisionHumano', 'MONEY')
                , T.Nodo.value('@comisionAutomatico', 'MONEY')
                , T.Nodo.value('@interes', 'DECIMAL(5,2)')
            FROM @datos.nodes('/Catalogos/Tipo_Cuenta_Ahorros/TipoCuentaAhorro') AS T(Nodo);

            -- tipos de operación de la bitácora
            INSERT INTO dbo.TipoOperacion (
                IdTipoOperacion
                , Nombre
            )
            SELECT T.Nodo.value('@id', 'INT')
                , T.Nodo.value('@nombre', 'VARCHAR(64)')
            FROM @datos.nodes('/Catalogos/TipoOperacionesBitacora/TipoOperacion') AS T(Nodo);

        COMMIT TRANSACTION tCargarCatalogo;

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
