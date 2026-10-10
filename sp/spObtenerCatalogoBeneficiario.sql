CREATE OR ALTER PROCEDURE dbo.spObtenerCatalogoBeneficiario
    @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spObtenerCatalogoBeneficiario
        @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- primer resultado: parentescos
        SELECT PA.IdParentesco
            , PA.Nombre
        FROM dbo.Parentesco AS PA
        ORDER BY PA.Nombre;

        -- segundo resultado: tipos de documento
        SELECT TDI.IdTipoDocuIdentidad
            , TDI.Nombre
        FROM dbo.TipoDocuIdentidad AS TDI
        ORDER BY TDI.IdTipoDocuIdentidad;

    END TRY
    BEGIN CATCH

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
